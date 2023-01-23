USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    dbo.usp_AddOrUpdateColumn
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2022-11-10
Description:	Adds a column if it does not exist by building and executing a dynamic SQL statment
Parameters:	    @database (varchar): the database name of the table the column is being added to or altered in
                @schema (varchar): the scehma name of the table the column is being added to or altered in
                @table (varchar): the table name the column is being added to or altered in
                @column (varchar): the name of the new column or the column being altered
                @dataType (varchar): the datatype of the new column or the column being altered - must be a valid datatype
                @allowNulls (bit): 0 (default) if NULL should not be allowed - 1 if NULL is allowed
                @updateColumn (bit): 0 (default) if new column - 1 if altering an existing column
                @debug (bit): 0 (default) to execute normally - 1 to return the constructed SQL script to the user
Return:		    N/A - operates directly on the table
Usage:		    EXEC LidoIM.dbo.usp_AddOrUpdateColumn 'LidoIM', 'dbo', 'tbl_Table', 'CreatedDateTime', 'datetime'
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2022-11-10      B Strathman     Created
***********************************************/

CREATE OR ALTER PROCEDURE [dbo].[usp_AddOrUpdateColumn] (
    @database varchar(200),
    @schema  varchar(200),
    @table  varchar(200),
    @column  varchar(200),
    @dataType varchar(500),
    @allowNulls bit = 0,
    @updateColumn bit = 0,
    @debug bit = 0
) AS
BEGIN
    SET NOCOUNT ON
    DECLARE 
        @ErrorMessage nvarchar(4000),
        @ErrorSeverity int = 16,
        @ErrorState int,
        @ErrorLine int,
        @ErrorNumber int;

    DECLARE 
        @newLine varchar(2) = CHAR(13) + CHAR(10),
        @nullable varchar(8) = '', 
        @sql nvarchar(4000) = '',
        @alterDataType varchar(500);

    SELECT @nullable = CASE WHEN @allowNulls = 0 THEN 'NOT NULL' ELSE 'NULL' END

    -- Handle computed columns
    SET @alterDataType = @dataType -- done this way as script for alter - fails when its a computed column
    IF SUBSTRING(LTrim(@dataType), 1, 2) = 'AS' AND @updateColumn = 1
    BEGIN
        PRINT 'Drop and recreate computed columns'
    END

    IF SUBSTRING(LTrim(@dataType), 1, 2) = 'AS' AND @updateColumn = 0
    BEGIN
        SET @alterDataType = 'int'
    END
    
    -- Construct the SQL to add or alter the column statement by statement
    SELECT @sql = @sql + FORMATMESSAGE('USE  %s ', @database) + @newLine
    IF @updateColumn = 0
    BEGIN
        SELECT @sql = @sql + FORMATMESSAGE('IF NOT exists (SELECT 1 from %s.INFORMATION_SCHEMA.COLUMNS C where TABLE_SCHEMA = ''%s'' And C.TABLE_NAME = ''%s'' And COLUMN_NAME = ''%s'')', @Database, @schema, @table, @column) + @newLine
        SELECT @sql = @sql + 'BEGIN ' + @newLine
        SELECT @sql = @sql + FORMATMESSAGE('    PRINT ''Adding Column %s in %s.%s.%s'' ', @column, @Database, @schema, @table) + @newLine
        SELECT @sql = @sql + FORMATMESSAGE('    ALTER TABLE %s.%s.%s ADD %s %s %s', @Database, @schema, @table, @column, @dataType, @nullable) + @newLine
        SELECT @sql = @sql + 'END ' + @newLine
    END

    IF @updateColumn = 1
    BEGIN
        SELECT @sql = @sql + 'BEGIN ' + @newLine
        SELECT @sql = @sql + '    IF ' + convert(varchar, @updateColumn) + ' = 1' + @newLine
        SELECT @sql = @sql + '    BEGIN ' + @newLine
        SELECT @sql = @sql + FORMATMESSAGE('    PRINT ''Altering column %s in %s.%s.%s'' ', @column, @Database, @schema, @table) + @newLine
        SELECT @sql = @sql + FORMATMESSAGE('        ALTER TABLE %s.%s.%s ALTER COLUMN %s %s %s', @Database, @schema, @table, @column, @alterDataType, @nullable) + @newLine
        SELECT @sql = @sql + '    END ' + @newLine
        SELECT @sql = @sql + '    ELSE ' + @newLine
        SELECT @sql = @sql + '    BEGIN ' + @newLine
        SELECT @sql = @sql + FORMATMESSAGE('        PRINT ''Column %s in table %s.%s.%s already exists ''', @column, @Database, @schema, @table) + @newLine
        SELECT @sql = @sql + '    END ' + @newLine
        SELECT @sql = @sql + 'END ' + @newLine
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

-- Termination branches
exitProc:
    RETURN;

error:
    RAISERROR (
        @ErrorMessage,  -- Message text.
        @ErrorSeverity, -- Severity.
        @ErrorState     -- State.
    );
    GOTO exitProc;

END
GO
