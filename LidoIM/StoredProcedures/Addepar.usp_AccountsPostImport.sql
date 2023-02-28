USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    Addepar.usp_AccountsPostImport
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2023-01-10
Description:	Scrubs and moves Addepar Accounts data from the dbimport.AddeparAccounts
                        import table to the Addepar.Accounts target table.
Parameters:	    N/A
Return:		    N/A
Usage:		    EXEC Addepar.usp_AccountsPostImport
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2023-01-10      B Strathman     Created
2023-02-28      B Strathman     Replaced the LidoAdvisor columns with five new columns: SeniorWealthAdvisor,
                                SeniorWealthManager1, SenorWealthManager2, MarketLeader, and PCS
***********************************************/

CREATE OR ALTER PROCEDURE [Addepar].[usp_AccountsPostImport]
AS
BEGIN
    SET NOCOUNT ON

    -- Create error handling variables
    DECLARE 
        @ErrorMessage nvarchar(4000),
        @ErrorSeverity int,
        @ErrorState int,
        @ErrorLine int,
        @ErrorNumber int;

    -- Create dbimport logging variables
    DECLARE 
        @RP_DUPLICATE       varchar(1) = 'D',
        @RP_ERROR           varchar(1) = 'E',
        @RP_PARTIAL         varchar(1) = 'P',       -- For 'IN_PROGRESS' recoreds left from the prior run
        @RP_IN_PROGRESS     varchar(1) = 'I',
        @RP_COMPLETE        varchar(1) = 'C'     

    -- Create a temp table to store post import actions to the dbimport table
    CREATE TABLE #outputTable (MergeAction varchar(20), InsertedID int, DeletedID int);
    

    -- Import table prep
    --*********************************************************************************************************************
    -- Delete any old records that no longer need to be retained
    DECLARE @daysToRetain int
    SELECT @daysToRetain = TRY_CONVERT(int, dbo.fn_GetSystemLookupValue('AddeparRecon', 'DaysToRetainAccountsImport'))
    PRINT('Deleting records in dbimport.AddeparAccounts older than ' + CAST(@daysToRetain AS varchar) + ' days.')

    -- If any records are still 'IN PROGRESS' from the prior run of the post-import proc, mark them as partial
    UPDATE dbimport.AddeparHoldings 
    SET RowProcessed = @RP_PARTIAL 
    WHERE RowProcessed = @RP_IN_PROGRESS
    
    -- Handle situations where fn_GetSystemLookupValue did not return a value or the return value cannot be parsed as an int
    DELETE FROM dbimport.AddeparAccounts 
    WHERE 
        CreatedDateTime < DATEADD(Day, -1 * ISNULL(@daysToRetain, 0), GETDATE())
        AND @daysToRetain IS NOT NULL 

    -- Mark any inactive rows as errors 
    PRINT('Marking inactive records in dbimport.AddeparAccounts as Errors')
    UPDATE dbimport.AddeparAccounts  
    SET 
        RowProcessed = @RP_ERROR,
        ModifiedDateTime = GETDATE(),
        ModifiedByUserID = SYSTEM_USER
    WHERE 
        Active = 0 
        AND RowProcessed IS NULL

    -- Check the PK of the target table
    -- Mark rows as errors if any PK columns are NULL or cannot be parsed to their target datatype
    -- Target PK: EntityID (int)
    PRINT('Marking records in dbimport.AddeparAccounts with an EntityID that cannot be parsed to an integer as Errors')
    UPDATE dbimport.AddeparAccounts 
    SET 
        RowProcessed = @RP_ERROR,
        ModifiedDateTime = GETDATE(),
        ModifiedByUserID = SYSTEM_USER
    WHERE 
        RowProcessed IS NULL 
        AND TRY_CONVERT(int, EntityID) IS NULL 

    -- Mark rows as duplicates if there are newer records with the same PK
    PRINT('Marking old, duplicate records in dbimport.AddeparAccounts as duplicates')
    ;WITH cteLatestUpdate AS (
        SELECT 
            MAX(RowID) AS MaxRowId,
            EntityID 
        FROM dbimport.AddeparAccounts
        WHERE RowProcessed IS NULL 
        GROUP BY EntityID
    )

    UPDATE t 
    SET 
        RowProcessed = @RP_DUPLICATE,
        ModifiedDateTime = GETDATE(),
        ModifiedByUserID = SYSTEM_USER
    FROM 
        dbimport.AddeparAccounts t
        INNER JOIN cteLatestUpdate c 
            ON t.EntityID = c.EntityID 
    WHERE 
        t.RowProcessed IS NULL 
        AND t.RowID <> c.MaxRowId


    -- Merge the scrubbed dbimport table with the target table
    --*********************************************************************************************************************
    BEGIN TRY
        BEGIN TRANSACTION;
            -- Mark all the remaining dbimport records as being processed
            UPDATE dbimport.AddeparAccounts  
            SET RowProcessed = @RP_IN_PROGRESS 
            WHERE RowProcessed IS NULL 

            -- Merge the dbimport table and the target table
            -- After the data scrubbing above, all the "in progress" dbimport records will have a unique, parsable PK
            PRINT('Merging dbimport.AddeparAccounts with Addepar.Accounts')
            ;MERGE Addepar.Accounts t 
            USING dbimport.AddeparAccounts s 
                ON t.EntityID = CAST(s.EntityID AS int) 
                AND s.RowProcessed = @RP_IN_PROGRESS 
            
            -- Update pre-existing Accounts
            -- The "Lido Advisor" columns (SeniorWealthAdvisor, SeniorWealthManager1, SeniorWealthManager2, MarketLeader, and PCS)
            -- are sometimes left NULL and sometimes filled with '-'. Override any instances of '-' with NULL.
            WHEN MATCHED AND s.RowProcessed = @RP_IN_PROGRESS THEN UPDATE SET 
                    AccountName         = s.AccountName,
                    AccountNumber       = s.AccountNumber,
                    Relationship        = s.Relationship,
                    InceptionDate       = TRY_CONVERT(date, s.InceptionDate),
                    Registration        = s.Registration,
                    AccountValue        = CAST(TRY_CONVERT(float, s.AccountValue) AS money),
                    SeniorWealthAdvisor = CASE WHEN RTRIM(LTRIM(s.SeniorWealthAdvisor)) = '-' THEN NULL ELSE s.SeniorWealthAdvisor END,
                    SeniorWealthManager1= CASE WHEN RTRIM(LTRIM(s.SeniorWealthManager1)) = '-' THEN NULL ELSE s.SeniorWealthManager1 END,
                    SeniorWealthManager2= CASE WHEN RTRIM(LTRIM(s.SeniorWealthManager2)) = '-' THEN NULL ELSE s.SeniorWealthManager2 END,
                    MarketLeader        = CASE WHEN RTRIM(LTRIM(s.MarketLeader)) = '-' THEN NULL ELSE s.MarketLeader END,
                    PCS                 = CASE WHEN RTRIM(LTRIM(s.PCS)) = '-' THEN NULL ELSE s.PCS END,
                    FinancialService    = s.FinancialService,
                    ErisaPooledPlan     = TRY_CONVERT(bit, s.ErisaPooledPlan),
                    Discretionary       = TRY_CONVERT(bit, s.Discretionary),
                    RiskProfile         = s.RiskProfile, 
                    RiskProfileDate     = TRY_CONVERT(date, s.RiskProfileDate),
                    TotalNetWorth       = CAST(TRY_CONVERT(float, s.TotalNetWorth) AS money),
                    LiquidNetWorth      = CAST(TRY_CONVERT(float, s.LiquidNetWorth) AS money),
                    OAccount            = TRY_CONVERT(bit, s.OAccount),
                    ModifiedDateTime    = GETDATE(),
                    ModifiedByUserID    = SYSTEM_USER 

            -- Insert new accounts into the target table
            WHEN NOT MATCHED BY TARGET AND s.RowProcessed = @RP_IN_PROGRESS THEN 
                    INSERT (EntityID, AccountName, AccountNumber, Relationship, InceptionDate, 
                            Registration, AccountValue, SeniorWealthAdvisor, SeniorWealthManager1, 
                            SeniorWealthManager2, MarketLeader, PCS, FinancialService, 
                            ErisaPooledPlan, Discretionary, RiskProfile, 
                            RiskProfileDate, TotalNetWorth, 
                            LiquidNetWorth, OAccount)
                    VALUES (CAST(s.EntityID AS int), s.AccountName, s.AccountNumber, s.Relationship, TRY_CONVERT(date, s.InceptionDate), 
                            s.Registration, CAST(TRY_CONVERT(float, s.AccountValue) AS money), 
                            CASE WHEN RTRIM(LTRIM(s.SeniorWealthAdvisor)) = '-' THEN NULL ELSE s.SeniorWealthAdvisor END, 
                            CASE WHEN RTRIM(LTRIM(s.SeniorWealthManager1)) = '-' THEN NULL ELSE s.SeniorWealthManager1 END,
                            CASE WHEN RTRIM(LTRIM(s.SeniorWealthManager2)) = '-' THEN NULL ELSE s.SeniorWealthManager2 END,
                            CASE WHEN RTRIM(LTRIM(s.MarketLeader)) = '-' THEN NULL ELSE s.MarketLeader END,
                            CASE WHEN RTRIM(LTRIM(s.PCS)) = '-' THEN NULL ELSE s.PCS END, s.FinancialService, 
                            TRY_CONVERT(bit, s.ErisaPooledPlan), TRY_CONVERT(bit, s.Discretionary), s.RiskProfile, 
                            TRY_CONVERT(date, s.RiskProfileDate), CAST(TRY_CONVERT(float, s.TotalNetWorth) AS money),
                            CAST(TRY_CONVERT(float, s.LiquidNetWorth) AS money), TRY_CONVERT(bit, s.OAccount))

            -- Set old accounts, no longer in the Addepar API query to inactive
            WHEN NOT MATCHED BY SOURCE THEN UPDATE SET 
                    Active              = 0,
                    ModifiedDateTime    = GETDATE(),
                    ModifiedByUserID    = SYSTEM_USER

            -- Log the merge actions to the #outputTable
            OUTPUT $action, inserted.EntityID 'inserted', deleted.EntityID 'deleted' 
            INTO #outputTable
            ;

            -- Update the rows in the temp table marking them as complete and processed
            UPDATE 
                dbimport.AddeparAccounts 
            SET 
                RowProcessed = @RP_COMPLETE,
                ModifiedDateTime = GETDATE(),
                ModifiedByUserID = SYSTEM_USER 
            WHERE 
                RowProcessed = @RP_IN_PROGRESS

            PRINT('Transaction completed without error - committing')
            GOTO commitProc

commitProc:
        COMMIT TRANSACTION;

        --SELECT 
        --    MergeAction, 
        --    COUNT(*) AS [RowCount]
        --FROM #outputTable
        --GROUP BY MergeAction

        DECLARE @rowsProcessed int
        SELECT @rowsProcessed = COUNT(*) FROM #outputTable

    END TRY
    BEGIN CATCH
        PRINT('Error encountered')
        SELECT 
            @ErrorMessage = ERROR_MESSAGE(),
            @ErrorLine = ERROR_LINE(),
            @ErrorNumber = ERROR_NUMBER(),
            @ErrorSeverity = ERROR_SEVERITY(),  
            @ErrorState = ERROR_STATE()

        ROLLBACK;

        GOTO error
    END CATCH

    GOTO exitProc

-- Termination Branches
exitProc:
    SELECT @rowsProcessed
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
