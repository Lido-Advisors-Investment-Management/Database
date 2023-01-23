USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    Addepar.usp_UpdateJobQueueStatus
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2023-01-13
Description:	Update the status of an Addepar job in the JobQueue table. The Addepar.JobQueue table
                        should only be updated through the use of this stored procedure. Before updating
                        the status of the job, this procedure will validate the passe d@UpdateToStatusId
                        and / or @UpdateToStatusName parameters and the @JobDetails value. This procedure
                        will also ensure that the ModifiedTimeStamp and ModifiedByUserID columns are 
                        updated in the JobQueue table.
Parameters:	    @JobQueueIdToUpdate (int): 
                @JobDetails (varchar): 
                @UpdateToStatusId (int, optional): 
                @UpdateToStatusName (varchar, optional): 
Return:		    bit: Success (1) or Failure (0) of updating the status of the job in the JobQueue table
Usage:		    EXEC Addepar.usp_UpdateJobQueueStatus @JobQueueIdToUpdate=1, @JobDetails='123456', @UpdateToStatusName='Posted'
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2023-01-13      B Strathman     Created
***********************************************/

CREATE OR ALTER PROCEDURE [Addepar].[usp_UpdateJobQueueStatus] (
    @JobQueueIdToUpdate int,
    @JobDetails varchar(500), 
    @UpdateToStatusId int = NULL,
    @UpdateToStatusName varchar(50) = NULL
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
        @ToStatusId int,
        @CurStatus int,
        @RowsUpdated int 

    -- Validate @UpdateToStatusId and @UpdateToStatusName
    --*********************************************************************************************************************
    -- Make sure one or the other was passed
    IF (@UpdateToStatusId IS NULL AND @UpdateToStatusName IS NULL) 
    BEGIN 
        PRINT 'A non-NULL value must be passed for either @UpdateToStatusID or @UpdateToStatusDescription'
        SELECT 0
        RETURN;
    END

    -- If both were passed, ensure they match and don't lead to all Statuses being filtered out
    SELECT @ToStatusId = ID
    FROM Addepar.JobStatus 
    WHERE 
        (ID = @UpdateToStatusId OR @UpdateToStatusId IS NULL) 
        AND (StatusName = @UpdateToStatusName OR @UpdateToStatusName IS NULL)

    IF (@ToStatusId IS NULL)
    BEGIN 
        PRINT 'Status not updated.'
        PRINT 'All statuses were filterd out between the passed @UpdateToStatusId and @UpdateToStatusName filters.'
        SELECT 0
        RETURN;
    END


    -- Work through each possible status and validate the @JobDetails parameter
    --*********************************************************************************************************************
    -- Disallow updating a status to Queued
    IF (@ToStatusId = 10) -- Queued 
    BEGIN 
        PRINT 'Cannot update status to "Queued". Status can only be set to "Queued" when the job is created.'
        SELECT 0
        RETURN;
    END 

    -- If the user is wanting to update the status to 'Posted' (to Addepar API), 'Imported', or 'Completed',
    -- ensure the passed @JobDetails value can be parsed into an integer
    IF (
        (TRY_CONVERT(int, @JobDetails) IS NULL) 
        AND (
            @ToStatusId = 20        -- Posted (to Addepar API): Expecting Addepar Job ID
            OR @ToStatusId = 40     -- Imported (to dbimport table): expecting number of rows imported
            OR @ToStatusId = 50     -- Completed (rows processed into target table): expecting number of rows processed
        )
    )
    BEGIN 
        PRINT 'Cannot update status to "Posted", "Imported", or "Completed" without a JobDetails value that can be parsed to an int.'
        SELECT 0
        RETURN;
    END 

    
    -- Update the status in the JobQueue table 
    --*********************************************************************************************************************
    BEGIN TRY
        -- ID is the PK of the Addepar.JobQueue table. This can only update a single record
        UPDATE Addepar.JobQueue 
        SET 
            StatusID            = @ToStatusId,
            JobDetails          = @JobDetails,
            ModifiedDateTime    = GETDATE(),
            ModifiedByUserID    = SYSTEM_USER 
        WHERE 
            ID = @JobQueueIdToUpdate

        SELECT @RowsUpdated = @@ROWCOUNT
        PRINT 'Updated ' + CAST(@RowsUpdated AS varchar) + ' job status'
        IF (@RowsUpdated = 0) 
        BEGIN 
            PRINT 'Provided JobQueue ID not found'
        END 

    END TRY
    BEGIN CATCH
        PRINT('Error encountered')
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
    SELECT @RowsUpdated
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
