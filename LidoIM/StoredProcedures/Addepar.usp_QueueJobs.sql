USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    Addepar.usp_QueueJobs
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2023-01-13
Description:	Procedue to queue Addepar API jobs based on the job definition parameters in 
                        Addepar.JobDefinition. This procedure was designed with the intention that it is
                        called by a daily SQL job, which will queue a set of Addepar jobs each morning. 
                        However,  
Parameters:	    @IdFilter (int, optional): Filter the ID column of the Job Definition table. Only 
                        queue the job with this passed ID. If left NULL, all jobs will be queued.
                        If an @IdFilter value is passed, the @NameFilter paramter should be left NULL.
                        Defaults to NULL.
                @NameFilter (varchar, optional): Filter the Name column of the Job Definition table. 
                        Only queue the job with this passed Name. If left NULL, all jobs will be queued.
                        If a @NameFilter value is passed, the @IdFilter paramter should be left NULL.
                        Defaults to NULL.
                @AsOfDateOverride (date, optional): The AsOfDate to queue the job for. If left NULL, 
                        the AsOfDate will default to the current date. Defaults to NULL.
                @ForceJob (bit, optional): If True (1), jobs will be queued even if they have been queued
                        or successfully run today. This parameter should be set to 1 when the earlier run
                        of the job successfully completed but there was an issue with the data queried 
                        from Addepar. Defaults to 0.
Return:		    int: The number of jobs queued into Addepar.JobQueue
Usage:		    EXEC Addepar.usp_QueueJobs
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2023-01-13      B Strathman     Created
***********************************************/

CREATE OR ALTER PROCEDURE [Addepar].[usp_QueueJobs] (
	@IdFilter int = NULL,
	@NameFilter varchar(50) = NULL,
	@AsOfDateOverride date = NULL,
	@ForceJob bit = 0
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
        @AsOfDate date,
        @StatusQueued int = 10,
		@StatusError int = 99,
        @JobsQueued int

	SELECT @AsOfDate = ISNULL(@AsOfDateOverride, GETDATE())


    -- Queue up the required jobs
    BEGIN TRY 
        -- Find the jobs that need to be queued now
        WITH cteJobsToRunNow AS (
            SELECT 
                j.ID, 
                @AsOfDate AS AsOfDate,
                cal.TradeDay AS IsTradeDate
            FROM 
                Addepar.JobDefinition j 
                LEFT JOIN dbo.TradeDateCalendar cal 
                    ON j.CalendarID = cal.CalendarID
                    AND cal.AsOfDate = @AsOfDate 
            WHERE 
                j.Active = 1 
                AND (j.ID = @IdFilter OR @IdFilter IS NULL) 
                AND (j.JobName = @NameFilter OR @NameFilter IS NULL)
                AND (
                    -- If user wants the jobs to be forced, ignore the RunTime of the job
                    -- If @AsOfDateOverride = NULL (automated job), only queue jobs after their start time
                    -- If a date override value was passed, queue it regardless of the time
                    @ForceJob = 1 
                    OR @AsOfDateOverride IS NOT NULL 
                    OR CAST(GETDATE() AS time) > j.StartTime
                )
        )
        -- If the job has already run today, don't queue it again unless the user wants the job to be forced
        -- to run again. Find the jobs that have been queued or run today, excluding jobs that errored out.
        ,cteRunJobsToday AS (
            SELECT DISTINCT 
                JobDefinitionID
            FROM 
                Addepar.JobQueue 
            WHERE 
                @ForceJob = 0
                AND Active = 1
                AND AsOfDate = @AsOfDate
                AND StatusID <> @StatusError
        )

        -- Only queue jobs where the AsOfDate is a trade date unless the @ForceJob parameter is set to True (1)
        INSERT INTO Addepar.JobQueue (JobDefinitionID, AsOfDate, StatusID, JobDetails)
        SELECT 
            a.ID, 
            a.AsOfDate,
            @StatusQueued,
            'Created'
        FROM 
            cteJobsToRunNow a
            LEFT JOIN cteRunJobsToday b 
                ON a.ID = b.JobDefinitionID 
        WHERE 
            b.JobDefinitionID IS NULL 
            AND (
                -- If user wants the jobs to be forced, don't care if the AsOfDate is a trade date or not
                -- If @AsOfDateOverride = NULL (automated job), only queue jobs on trade dates of their calendar
                -- If a date override value was passed, queue it regardless
                @ForceJob = 1
                OR @AsOfDateOverride IS NOT NULL 
                OR a.IsTradeDate = 1
            )

        SELECT @JobsQueued = @@ROWCOUNT
        PRINT CAST(@JobsQueued AS varchar) + ' jobs queued into Addepar.JobQueue'

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
    RETURN @JobsQueued;

error:
    RAISERROR (
        @ErrorMessage,  -- Message text.
        @ErrorSeverity, -- Severity.
        @ErrorState     -- State.
    );
    GOTO exitProc;
END
GO
