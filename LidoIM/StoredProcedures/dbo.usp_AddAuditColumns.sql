USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    dbo.usp_AddAuditColumns
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2022-11-10
Description:	Adds the 5 standard audit columns to a table
Parameters:	    @database (varchar): the database name of the table to which the audit columns are being added
                @schema (varchar): the scehma name of the table to which the audit columns are being added
                @table (varchar): the table name to which the audit columns are being added
                @column (varchar): the name of the new column or the column being altered
                @newTable (bit): 0 (debug) if adding the columns to an existing table - 1 if adding to a new table
                @debug (bit): 0 (default) to execute normally - 1 to return the constructed SQL script to the user
Return:		    N/A - operates directly on the table
Usage:		    EXEC LidoIM.dbo.usp_AddAuditColumns 'LidoIM', 'dbo', 'tbl_Table', @newTable=1
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2022-11-10      B Strathman     Created
***********************************************/

CREATE OR ALTER PROCEDURE [dbo].[usp_AddAuditColumns] (
    @database varchar(200),
    @schema  varchar(200),
    @table  varchar(200),
    @newTable bit = 0
) AS
BEGIN
    SET NOCOUNT ON
    DECLARE 
        @ErrorMessage nvarchar(4000),
        @ErrorSeverity int,
        @ErrorState int,
        @ErrorLine int,
        @ErrorNumber int;

    DECLARE
        @newLine varchar(2) = CHAR(13) + CHAR(10),
        @sql nvarchar(4000) = '';

    -- Attempt to execute the constructed SQL to add or alter the column
    BEGIN TRY
        IF @newTable = 0
        BEGIN
            -- Add all the audit columns (@allowNulls=1)
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'CreatedDateTime', 'datetime', 1
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'CreatedByUserID', 'nvarchar(128)', 1
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'ModifiedDateTime', 'datetime', 1
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'ModifiedByUserID', 'nvarchar(128)', 1
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'Active', 'bit', 1

            -- Backfill all the audit columns
            PRINT @newLine + 'Backfilling the audit columns'
            SELECT @sql = FORMATMESSAGE('UPDATE %s.%s.%s ', @database, @schema, @table)
            SELECT @sql = @sql + 'SET CreatedDateTime = GetDate(), CreatedByUserID = ''historical'', ModifiedDateTime = GetDate(), ModifiedByUserID = ''historical'', Active = 1;'
            PRINT @sql + @newLine
            EXEC sp_executesql @sql

            -- Add all the default constraints to the audit columns
            EXEC LidoIM.dbo.usp_AddConstraint @database, @schema, @table, 'CreatedDateTime', 'df', 'GETDATE()'
            EXEC LidoIM.dbo.usp_AddConstraint @database, @schema, @table, 'CreatedByUserID', 'df', 'SYSTEM_USER'
            EXEC LidoIM.dbo.usp_AddConstraint @database, @schema, @table, 'ModifiedDateTime', 'df', 'GETDATE()'
            EXEC LidoIM.dbo.usp_AddConstraint @database, @schema, @table, 'ModifiedByUserID', 'df', 'SYSTEM_USER'
            EXEC LidoIM.dbo.usp_AddConstraint @database, @schema, @table, 'Active', 'df', '1'
            PRINT ''

            -- Update all the audit columns to not allow NULLs (@allowNulls=0, @updateColumn=1)
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'CreatedDateTime', 'datetime', 0, 1
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'CreatedByUserID', 'nvarchar(128)', 0, 1
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'ModifiedDateTime', 'datetime', 0, 1
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'ModifiedByUserID', 'nvarchar(128)', 0, 1
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'Active', 'bit', 0, 1

        END
        IF @newTable = 1
        BEGIN
            -- Add all the audit columns (@allowNulls=0)
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'CreatedDateTime', 'datetime', 0
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'CreatedByUserID', 'nvarchar(128)', 0
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'ModifiedDateTime', 'datetime', 0
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'ModifiedByUserID', 'nvarchar(128)', 0
            EXEC LidoIM.dbo.usp_AddOrUpdateColumn @database, @schema, @table, 'Active', 'bit', 0
            PRINT ''

            -- Add all the default constraints to the audit columns
            EXEC LidoIM.dbo.usp_AddConstraint @database, @schema, @table, 'CreatedDateTime', 'df', 'GETDATE()'
            EXEC LidoIM.dbo.usp_AddConstraint @database, @schema, @table, 'CreatedByUserID', 'df', 'SYSTEM_USER'
            EXEC LidoIM.dbo.usp_AddConstraint @database, @schema, @table, 'ModifiedDateTime', 'df', 'GETDATE()'
            EXEC LidoIM.dbo.usp_AddConstraint @database, @schema, @table, 'ModifiedByUserID', 'df', 'SYSTEM_USER'
            EXEC LidoIM.dbo.usp_AddConstraint @database, @schema, @table, 'Active', 'df', '1'
        END
    END TRY
    BEGIN CATCH
        SELECT 
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorLine = ERROR_LINE(),
            @ErrorNumber = ERROR_NUMBER(),
            @ErrorSeverity = ERROR_SEVERITY(),  
            @ErrorState = ERROR_STATE()

        GOTO error
    END CATCH

-- Termination Branches
exitProc:
    return;

error:
    RAISERROR (
        @ErrorMessage,  -- Message text.
        @ErrorSeverity, -- Severity.
        @ErrorState     -- State.
    );
    goto exitProc;
END
GO
