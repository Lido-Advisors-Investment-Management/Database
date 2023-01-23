USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		dbo.usp_PandasCalendarsToDownload
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2023-01-06
Description:	Return a table of trade calendars that need to be updated along with start and end datas defining 
                        the time period over which to update each trade calendar.
Parameters:	@lookBackDays (int, optional): The amount of historical days in the past to reload to the database. 
                        Defaults to 30 days.
                @lookForwardDays (int, optional): The amount of future, projected days to reload to the database. 
                        Defaults to 730 days (2 years).
                @calendarIdFilter (int, optional): Filter the PandasCalendarCode tbale and only update data for the
                        particular calendar specified by the databsae calendar ID. If no filter is passed, all active
                        calendars will be returned. Defults to NULL.
                        * The calendar ID column is the PK of the table and therefore unique. 
                        **THIS PARAMETER IS NOT VALIDATED - If the passed calendar ID does not exists, no calendar
                        will be returned and therefore no calendar will be updated.
                @pandasCodeFilter (int, optional): Filter the PandasCalendarCode tbale and only update data for the
                        particular calendars specified by the Pandas calendar code ID. If no filter is passed, all 
                        active calendars will be returned. Defults to NULL.
                        * The Pandas calendar ID column is NOT unique. Its possible that multiple databse calendar
                        IDs map to the same Pandas calendar code.
                        **THIS PARAMETER IS NOT VALIDATED - If the passed Pandas calendar ID does not exists, no 
                        calendar will be returned and therefore no calendar will be updated.
Return:		table with 4 columns
                        [ DatabaseID  |  PandasCode  |  StartDate  |  EndDate ]
Usage:		EXEC dbo.usp_PandasCalendarsToDownload
                EXEC dbo.usp_PandasCalendarsToDownload @lookBackDays=1826, @lookForwardDays=0, @pandasCodeFilter='NYSE'
Repo:		        Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2023-01-06      B Strathman     Created
***********************************************/

CREATE OR ALTER PROCEDURE [dbo].[usp_PandasCalendarsToDownload] (
	@lookBackDays int = 30,
	@lookForwardDays int = 730,	    -- 2 years
	@calendarIdFilter int = NULL,
	@pandasCodeFilter varchar(50) = NULL
) AS
BEGIN
    SET NOCOUNT ON

    -- Query the active calendars from the PandasCalendarCode table with start and stop dates
    SELECT 
        ID AS DatabaseID,
        PandasCode,
        CAST(DATEADD(Day, -@lookBackDays, GETDATE()) AS date) AS StartDate,
        CAST(DATEADD(Day, @lookForwardDays, GETDATE()) AS date) AS EndDate
    FROM 
        dbo.PandasCalendarCode
    WHERE 
        Active = 1 
        AND (@calendarIdFilter IS NULL OR ID = @calendarIdFilter) 
        AND (@pandasCodeFilter IS NULL OR PandasCode = @pandasCodeFilter) 
END
GO
