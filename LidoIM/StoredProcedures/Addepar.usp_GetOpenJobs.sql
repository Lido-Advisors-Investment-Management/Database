USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    Addepar.usp_GetOpenJobs
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2023-01-13
Description:	Get a list of all open jobs along with the job detail values critical to the next step
Parameters:	    @JobIdFilter (int, optional): Filter the results by the Job ID. If left NULL, all results
                        will be returns. Defaults to NULL.
                @JobDefinitionIdFilter (int, optional): Filter the results by the Job Definition ID. 
                        If left NULL, all results will be returns. Defaults to NULL.
                @JobStatusIdFilter (int, optional): Filter the results by the Job Status ID. If left NULL, 
                        all results will be returns. Defaults to NULL.
Return:		    Table with all the open jobs and the required job details to complete the next step
                        ID (int): The unique ID associated with the job in the JobQueue table
                        JobName (varchar): The name of the job that is queued (ref Addepar.JobDefintion)
                        AsOfDate (date): The date as of which the job is being run for (not necessarily 
                                the current date)
                        StatusName (varchar): The current status name of the job (ref Addepar.JobStatus)
                        QueryParameters (varchar): The information required for the next step of the job.
                                Queued: the API parameters 
Usage:		    EXEC Addepar.usp_GetOpenJobs
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2023-01-13      B Strathman     Created
***********************************************/

CREATE OR ALTER PROCEDURE [Addepar].[usp_GetOpenJobs] (
    @JobIdFilter int = NULL,
    @JobDefinitionIdFilter int = NULL,
    @JobStatusIdFilter int = NULL
) AS
BEGIN
    SET NOCOUNT ON
    DECLARE 
        @ErrorMessage nvarchar(4000),
        @ErrorSeverity int,
        @ErrorState int,
        @ErrorLine int,
        @ErrorNumber int;

    -- Proc SQL
    BEGIN TRY

        WITH cteJobDates AS (
            SELECT 
                q.ID,
                q.JobDefinitionID,
                q.AsOfDate,
                q.StatusID,
                s.StatusName,
                q.JobDetails,
                dbo.fn_TradeDateAdd('Day', d.RelativeStartDate, q.AsOfDate, d.CalendarID, 0) AS StartDate,
                dbo.fn_TradeDateAdd('Day', d.RelativeEndDate, q.AsOfDate, d.CalendarID, 0) AS EndDate
            FROM 
                Addepar.JobQueue q 
                INNER JOIN Addepar.JobStatus s 
                    ON q.StatusID = s.ID 
                    AND s.IsJobOpen = 1
                LEFT JOIN Addepar.JobDefinition d 
                    ON q.JobDefinitionID = d.ID
            WHERE 
                q.Active = 1
                AND (q.ID = @JobIdFilter OR @JobIdFilter IS NULL)
                AND (q.JobDefinitionID = @JobDefinitionIdFilter OR @JobDefinitionIdFilter IS NULL)
                AND (q.StatusID = @JobStatusIdFilter OR @JobStatusIdFilter IS NULL)
        )

        -- Return the required information for the next step in the Addepar Job API Query
        --      1. If the job is created and needs to be posted, return the API Query paramters
        --      2. If the job has been posted to Addepar, return the Job ID to check the status
        --      3. If the job has been downloaded, return the ImportProcName with the file name
        --      4. If the job has been imported, return the formatted PostImportProcName
        SELECT 
            c.ID,
            d.JobName,
            c.AsOfDate,
            c.StatusName,
            CASE 
                WHEN c.StatusID = 10 THEN REPLACE(REPLACE(QueryParameters, '__StartDate__', c.StartDate), '__EndDate__', c.EndDate)
                WHEN c.StatusID = 20 THEN c.JobDetails 
                WHEN c.StatusID = 30 THEN ('EXEC ' + d.ImportProcName + ' @filePath=''' + c.JobDetails + '''')
                WHEN c.StatusID = 40 THEN 
                    CASE 
                        WHEN d.PostImportProcParameters IS NULL THEN 'EXEC ' + d.PostImportProcName
                        ELSE 'EXEC ' + d.PostImportProcName + ' ' + d.PostImportProcParameters + '=''' + CAST(c.EndDate AS varchar) + ''''
                    END
                ELSE NULL
                END
                AS QueryParameters 
        FROM 
            cteJobDates c
            LEFT JOIN Addepar.JobDefinition d 
                ON c.JobDefinitionID = d.ID

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

-- Termination Branches
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
