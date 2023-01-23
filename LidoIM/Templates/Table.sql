
/***********************************************
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2022-11-10

Description	
This template can be used to create a table. 
    1. Find and replace-all (Ctrl + H) each of the following variables
        a. databaseName
        b. schemaName
        c. tableName
    2. Populate the required columns with datatypes and NULL / NOT NULL
    3. Add any required constraints - these can be copies into the CREATE statement is desired
***********************************************/

USE databaseName
GO

DECLARE
    @database varchar(200) = 'databaseName',
    @schema varchar(200) = 'schemaName',
    @table varchar(200) = 'tableName'

-- Ensure the table doens't exist
IF NOT Exists(SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'schemaName' And TABLE_NAME = 'tableName') 
BEGIN

    CREATE TABLE [schemaName].[tableName] (
        --=========================================
        -- Add columns here - default audit columns will be added below
        -- ColumnName1  int             NOT NULL,
        -- ColumnName2  varchar(100)    NULL
        --=========================================
        
    );
    PRINT 'Table created';

    EXEC LidoIM.dbo.usp_AddAuditColumns @database, @schema, @table, @newTable=1;
    PRINT 'Default, audit columns added'

    -- Add any required constraints here. Templates: 
    -- Default: ALTER TABLE [schemaName].[tableName] ADD CONSTRAINT df_tableName_columnName DEFAULT (value) FOR columnName;
    -- Unique:  ALTER TABLE [schemaName].[tableName] ADD CONSTRAINT ak_tableName_columnName UNIQUE(columnName);
    -- Check:   ALTER TABLE [schemaName].[tableName] ADD CONSTRAINT chk_tableName_columnName CHECK(columnName > 0);
    -- PK:      ALTER TABLE [schemaName].[tableName] ADD CONSTRAINT pk_tableName_columnName PRIMARY KEY CLUSTERED (columnName, columnName2);
    -- FK:      ALTER TABLE [schemaName].[tableName] ADD CONSTRAINT fk_foreignTable_foreignColumn_tableName FOREIGN KEY (columnName) REFERENCES foreignSchema.foreignTable (foreignColumn);

END
ELSE 
BEGIN 
    PRINT 'Error: table already exists.'
END