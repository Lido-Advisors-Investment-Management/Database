USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    dbo.usp_AddConstraint
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2022-11-10
Description:	Adds a constraint to an existing table column
Parameters:	    @database (varchar): the database name of the table to which the constraint is being added
                @schema (varchar): the scehma name of the table to which the constraint is being added
                @table (varchar): the table name to which the constraint is being added
                @column (varchar): the column name to which the constraint is being added
                @constraintType (varchar): 
                    df: default
                @constraintText (varchar): the text required to create the specified constraint
                    df: the defualt value
                @debug (bit): 0 (default) to execute normally - 1 to return the constructed SQL script to the user
Return:		    N/A - operates directly on the table
Usage:		    EXEC LidoIM.dbo.usp_AddConstraint 'LidoIM', 'dbo', 'tbl_Table', 'CreatedDateTime', 'df', 'GETDATE()'
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2022-11-10      B Strathman     Created
***********************************************/

CREATE OR ALTER PROCEDURE [dbo].[usp_AddConstraint] (
    @database varchar(200),
    @schema  varchar(200),
    @table  varchar(200),
    @column  varchar(200),
    @constraintType varchar(5),
    @constraintText varchar(200),
    @debug bit = 0
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

    -- Proc SQL
    IF @constraintType = 'df'
    BEGIN
        SELECT @sql = FORMATMESSAGE('USE  %s ', @database) + @newLine
        SELECT @sql = @sql + FORMATMESSAGE('IF exists (SELECT 1 from %s.INFORMATION_SCHEMA.COLUMNS C where TABLE_SCHEMA = ''%s'' And C.TABLE_NAME = ''%s'' And COLUMN_NAME = ''%s'')', @Database, @schema, @table, @column) + @newLine
        SELECT @sql = @sql + 'BEGIN ' + @newLine
        SELECT @sql = @sql + FORMATMESSAGE('    PRINT ''Adding default value (%s) to %s in %s.%s.%s''', @constraintText, @column, @Database, @schema, @table) + @newLine
        SELECT @sql = @sql + FORMATMESSAGE('    ALTER TABLE %s.%s ADD CONSTRAINT [df_%s_%s] DEFAULT (%s) FOR [%s];', @schema, @table, @table, @column, @constraintText, @column)
        SELECT @sql = @sql + 'END ' + @newLine
    END
    ELSE 
    BEGIN
        PRINT FORMATMESSAGE('Error: %s is not a recognized constraint type.', @constraintType)
        GOTO exitProc
    END

    -- Attempt to execute the constructed SQL to add or alter the column
    BEGIN TRY
        IF (@debug = 1)
        BEGIN
            PRINT @sql
        END
        ELSE
        BEGIN
            EXEC sp_executesql @sql
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
