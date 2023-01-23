USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    dbimport.usp_ImportAddeparHoldings
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2023-01-10
Description:	Import the JSON file specified by @filePath parameter containing the entire firm's holdings and
                        load it to the dbimport.AddeparHoldings table. This stored procedure will be called 
                        by the SSIS package managing the job.
Parameters:	    @filePath (varchar): full file path and name of the Addepar Holdings JSON file to import
                @debug (bit): 0 (default) to execute normally - 1 to return the constructed SQL script to the user
Return:		    int: number of rows inserted into dbimport.AddeparHoldings
Usage:		    EXEC dbimport.usp_ImportAddeparHoldings @filePath='C:\Users\bstrathman\Documents\FirmHoldings_20230109.json'
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2023-01-10      B Strathman     Created
***********************************************/

CREATE OR ALTER PROCEDURE [dbimport].[usp_ImportAddeparHoldings] (
    @filePath varchar(500),
    @debug bit = 0
) AS
BEGIN
    SET NOCOUNT ON

    -- Create error handling variables
    DECLARE 
        @ErrorMessage nvarchar(4000),
        @ErrorSeverity int,
        @ErrorState int,
        @ErrorLine int,
        @ErrorNumber int;

    -- Create variables to import the JSON data
    DECLARE 
		@sql nvarchar(MAX),
		@acctData varchar(MAX),
        @rowsInserted int

	-- Build and execute the SQL to import the JSON file
	SELECT @sql = N'SELECT @jsonData = BulkColumn FROM OPENROWSET(BULK ''' + @filePath + ''', SINGLE_BLOB) JSON;'

    -- Attempt to execute the constructed SQL to import the JSON file
    BEGIN TRY
        IF (@debug = 1)
        BEGIN
            PRINT @sql
            GOTO exitProc
        END
        ELSE
        BEGIN
            EXEC sp_executesql @sql, N'@jsonData varchar(MAX) OUTPUT', @jsonData=@acctData OUTPUT;
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
    
    -- Parse the JSON data and load it to dbimport.AddeparHoldings
    BEGIN TRY
        INSERT INTO dbimport.AddeparHoldings(EntityID, AsOfDate, AccountNumber, SecurityName, CUSIP, Symbol, FlyerAssetClass, 
                                                Strategy, Quantity, Price, Notional, PurchaseDate, ImportFileName)
        SELECT 
            JSON_VALUE(sec.Value, '$.entity_id') AS EntityID,
            JSON_VALUE(sec.Value, '$.columns.holding_end_date') AS AsOfDate,
            JSON_VALUE(acct.Value, '$.name') AS AccountNumber,
            JSON_VALUE(sec.Value, '$.name') AS SecurityName,
            JSON_VALUE(sec.Value, '$.columns.cusip') AS CUSIP,
            JSON_VALUE(sec.Value, '$.columns._custom_symbol_260903') AS Symbol,
            JSON_VALUE(sec.Value, '$.columns._custom_flyer_asset_class_605825') AS FlyerAssetClass,
            JSON_VALUE(sec.Value, '$.columns._custom_strategy_115494') AS Strategy,
            JSON_VALUE(sec.Value, '$.columns.shares') AS Quantity,
            JSON_VALUE(sec.Value, '$.columns.price_per_share') AS Price,
            JSON_VALUE(sec.Value, '$.columns.value') AS Notional,
            JSON_VALUE(sec.Value, '$.columns.purchase_date') AS PurchaseDate,
            @filePath AS ImportFileName
        FROM 
            OPENJSON(@acctData, '$.data.attributes.total.children') AS acct
            CROSS APPLY OPENJSON(acct.Value, '$.children') AS sec

        SELECT @rowsInserted = @@ROWCOUNT
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
    SELECT @rowsInserted
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
