USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    Addepar.usp_HoldingsPostImport
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2023-01-10
Description:	Scrubs and moves Addepar Holdings data from the dbimport.AddeparHoldings
                        import table to the Addepar.Holdings target table.
Parameters:	    @targetDate (date): only records with an AsOfDate equal to this @targetDate will be processed.
                        If NULL< the procedure will default to the latest AsOfDate with a NULL RowProcessed value
                        in the dbimport table after it is scrubbed.
                        Defults to NULL.
Return:		    int: number of rows processed from the dbimport table
Usage:		    EXEC Addepar.usp_HoldingsPostImport
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2023-01-10      B Strathman     Created
***********************************************/

CREATE OR ALTER PROCEDURE [Addepar].[usp_HoldingsPostImport](
    @targetDate date = NULL
)
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

    DECLARE 
        @rowsDeleted int,
        @rowsInserted int
   

    -- Import table prep
    --*********************************************************************************************************************
    -- Delete any old records that no longer need to be retained
    DECLARE @daysToRetain int
    SELECT @daysToRetain = TRY_CONVERT(int, dbo.fn_GetSystemLookupValue('AddeparRecon', 'DaysToRetainHoldingsImport'))
    PRINT('Deleting records in dbimport.AddeparHoldings older than ' + CAST(@daysToRetain AS varchar) + ' days.')

    -- If any records are still 'IN PROGRESS' from the prior run of the post-import proc, mark them as partial
    UPDATE dbimport.AddeparHoldings 
    SET RowProcessed = @RP_PARTIAL 
    WHERE RowProcessed = @RP_IN_PROGRESS

    -- Handle situations where fn_GetSystemLookupValue did not return a value or the return value cannot be parsed as an int
    DELETE FROM dbimport.AddeparHoldings 
    WHERE 
        CreatedDateTime < DATEADD(Day, -1 * ISNULL(@daysToRetain, 0), GETDATE())
        AND @daysToRetain IS NOT NULL 

    -- Mark any inactive rows as errors 
    PRINT('Marking inactive records in dbimport.AddeparHoldings as Errors')
    UPDATE dbimport.AddeparHoldings  
    SET 
        RowProcessed = @RP_ERROR,
        ModifiedDateTime = GETDATE(),
        ModifiedByUserID = SYSTEM_USER
    WHERE 
        Active = 0 
        AND RowProcessed IS NULL

    -- Check the PK of the target table
    -- Mark rows as errors if any PK columns are NULL or cannot be parsed to their target datatype
    -- Target PK: AsOfDate (date), AccountNumber (varchar(20)), EntityID (int)
    PRINT('Marking records in dbimport.AddeparHoldings with an AsOfDate, AccountNumber, or EntityID that cannot be parsed as Errors')
    UPDATE dbimport.AddeparHoldings 
    SET 
        RowProcessed = @RP_ERROR,
        ModifiedDateTime = GETDATE(),
        ModifiedByUserID = SYSTEM_USER
    WHERE 
        RowProcessed IS NULL 
        AND (
            TRY_CONVERT(date, AsOfDate) IS NULL
            OR AccountNumber IS NULL OR LEN(AccountNumber) > 20
            OR TRY_CONVERT(int, EntityID) IS NULL
        )

    -- Mark rows as duplicates if there are newer records with the same PK
    PRINT('Marking old, duplicate records in dbimport.AddeparHoldings as duplicates')
    ;WITH cteLatestUpdate AS (
        SELECT 
            MAX(RowID) AS MaxRowId,
            AsOfDate,
            AccountNumber,
            EntityID 
        FROM dbimport.AddeparHoldings
        WHERE RowProcessed IS NULL 
        GROUP BY AsOfDate, AccountNumber, EntityID
    )

    UPDATE t 
    SET 
        RowProcessed = @RP_DUPLICATE,
        ModifiedDateTime = GETDATE(),
        ModifiedByUserID = SYSTEM_USER
    FROM 
        dbimport.AddeparHoldings t
        INNER JOIN cteLatestUpdate c 
            ON t.AsOfDate = c.AsOfDate 
            AND t.AccountNumber = c.AccountNumber
            AND t.EntityID = c.EntityID 
    WHERE 
        t.RowProcessed IS NULL 
        AND t.RowID <> c.MaxRowId


    -- If no @targetDate was passed, find the latest unprocessed AsOfDate in the dbimport.AddeparHoldings table
    IF @targetDate IS NULL
    BEGIN 
        SELECT TOP 1 @targetDate = AsOfDate 
        FROM dbimport.AddeparHoldings 
        WHERE RowProcessed IS NULL 
        ORDER BY AsOfDate DESC 
    END
    
    -- If @targetDate is not the T-1 close, print a warning
    DECLARE @tMinusDate date = dbo.fn_TradeDateAdd('Day', -1, GETDATE(), 1, 0)
    IF @targetDate <> @tMinusDate 
    BEGIN 
        PRINT('Warning: @targetDate is not the T-1 date')
    END

    -- Move the dbimport records to the target table
    --*********************************************************************************************************************
    -- A merge statement would be ideal here but is too slow. Also all old / existing data in the target table
    -- should be removed anyways, which reduces the need for a merge statement.
    BEGIN TRY
        BEGIN TRANSACTION;
            -- Mark all the remaining dbimport records as being processed
            UPDATE dbimport.AddeparHoldings  
            SET RowProcessed = @RP_IN_PROGRESS 
            WHERE 
                RowProcessed IS NULL 
                AND CAST(AsOfDate AS date) = @targetDate 

            -- Delete all the records currently in Addepar.Holdings with the @targetDate AsOfDate 
            DELETE Addepar.Holdings 
            WHERE AsOfDate = @targetDate 

            SELECT @rowsDeleted = @@ROWCOUNT
            PRINT(CAST(@rowsDeleted AS varchar) + ' records deleted from Addepar.Holdings')


            -- Insert all the dbimport records into Addepar.Holdings
            INSERT INTO Addepar.Holdings (AsOfDate, AccountNumber, EntityID, SecurityName, CUSIP, Symbol, 
                                            FlyerAssetClass, Strategy, Quantity, Price, Notional, PurchaseDate)
            SELECT 
                CAST(AsOfDate AS date), 
                AccountNumber, 
                CAST(EntityID AS int), 
                SecurityName, 
                CUSIP, 
                Symbol, 
                FlyerAssetClass, 
                Strategy,
                CAST(TRY_CONVERT(float, Quantity) AS decimal(38, 20)), 
                CAST(TRY_CONVERT(float, Price) AS decimal(38, 20)), 
                CAST(TRY_CONVERT(float, Notional) AS decimal(38, 20)), 
                TRY_CONVERT(date, PurchaseDate)
            FROM 
                dbimport.AddeparHoldings
            WHERE 
                RowProcessed = @RP_IN_PROGRESS

            SELECT @rowsInserted = @@ROWCOUNT
            PRINT(CAST(@rowsInserted AS varchar) + ' records inserted into Addepar.Holdings')


            -- Update the rows in the temp table marking them as complete and processed
            UPDATE 
                dbimport.AddeparHoldings 
            SET 
                RowProcessed = @RP_COMPLETE,
                ModifiedDateTime = GETDATE(),
                ModifiedByUserID = SYSTEM_USER 
            WHERE 
                RowProcessed = @RP_IN_PROGRESS

            PRINT('Transactions completed without error - committing')
            GOTO commitProc

commitProc:
        COMMIT TRANSACTION;

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
