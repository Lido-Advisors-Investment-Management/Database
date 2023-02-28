USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    dbimport.usp_ImportAddeparAccounts
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2023-01-10
Description:	Import the JSON file specified by @filePath parameter containing all the entire firm's accounts
                        and load it to the dbimport.AddeparAccounts table. This stored procedure will be called 
                        by the SSIS package managing the job.
Parameters:	    @filePath (varchar): full file path and name of the Addepar Accounts JSON file to import
                @debug (bit): 0 (default) to execute normally - 1 to return the constructed SQL script to the user
Return:		    int: number of rows inserted into dbimport.AddeparAccountss
Usage:		    EXEC dbimport.usp_ImportAddeparAccounts @filePath='C:\Users\bstrathman\Documents\FirmAccounts_20230109.json'
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2023-01-10      B Strathman     Created
2023-02-28      B Strathman     Replaced the LidoAdvisor columns with five new columns: SeniorWealthAdvisor,
                                SeniorWealthManager1, SenorWealthManager2, MarketLeader, and PCS
***********************************************/

CREATE OR ALTER PROCEDURE [dbimport].[usp_ImportAddeparAccounts] (
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
    
    -- Parse the JSON data and load it to dbimport.AddeparAccounts
    BEGIN TRY
        INSERT INTO dbimport.AddeparAccounts (EntityID, AccountName, AccountNumber, Relationship, InceptionDate, Registration, 
                                                AccountValue, SeniorWealthAdvisor, SeniorWealthManager1, SeniorWealthManager2, 
                                                MarketLeader, PCS, FinancialService, ErisaPooledPlan, Discretionary, 
                                                RiskProfile, RiskProfileDate, TotalNetWorth, LiquidNetWorth, OAccount, ImportFileName)
        SELECT 
            JSON_VALUE(grp.Value, '$.entity_id') AS EntityID,
            JSON_VALUE(grp.Value, '$.name') AS AccountName,
            JSON_VALUE(grp.Value, '$.columns._custom_account_289300') AS AccountNumber,
            JSON_VALUE(grp.Value, '$.columns.top_level_owner') AS Registration,
            JSON_VALUE(grp.Value, '$.columns.inception_event_date') AS InceptionDate,
            JSON_VALUE(grp.Value, '$.columns._custom_registration_298373') AS Registration,
            JSON_VALUE(grp.Value, '$.columns.value') AS AccountValue,
            JSON_VALUE(grp.Value, '$.columns._custom_senior_wealth_advisor_bdo_978077') AS SeniorWealthAdvisor,
            JSON_VALUE(grp.Value, '$.columns._custom_senior_wealth_manager_978078') AS SeniorWealthManager1,
            JSON_VALUE(grp.Value, '$.columns._custom_copy_of_senior_wealth_manager_2_978079') AS SeniorWealthManager2,
            JSON_VALUE(grp.Value, '$.columns._custom_market_leader_978076') AS MarketLeader,
            JSON_VALUE(grp.Value, '$.columns._custom_pcs_1195051') AS PCS,
            JSON_VALUE(grp.Value, '$.columns.financial_service') AS FinancialService,
            JSON_VALUE(grp.Value, '$.columns._custom_erisa_pooled_plan_698408') AS ErisaPooledPlan,
            JSON_VALUE(grp.Value, '$.columns._custom_discretionary_298374') AS Discretionary,
            JSON_VALUE(grp.Value, '$.columns._custom_risk_profile_325712') AS RiskProfile,
            JSON_VALUE(grp.Value, '$.columns._custom_rp_date_334786') AS RiskProfileDate,
            JSON_VALUE(grp.Value, '$.columns._custom_total_net_worth_lido_328933') AS TotalNetWorth,
            JSON_VALUE(grp.Value, '$.columns._custom_total_net_worth_lido2_328946') AS LiquidNetWorth,
            JSON_VALUE(grp.Value, '$.columns._custom_oaccount_272353') AS OAccount,
            @filePath AS ImportFileName
        FROM 
            OPENJSON(@acctData, '$.data.attributes.total.children') AS grp

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
