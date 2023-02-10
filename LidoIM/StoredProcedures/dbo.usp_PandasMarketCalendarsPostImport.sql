USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    dbo.usp_PandasMarketCalendarsPostImport
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2023-01-10
Description:	Updates data in dbo.TradeDateCalendar for a given trade calendar using raw data
                        in dbimport.PandasMarketCalendars
Parameters:	    @CalendarId (int): The CalendarID of the calendar and data to update. Reference
                        dbo.PnadasCalendarCode table for IDs.
                @StartDate (date, optional): The date to begin updating the dbo.TradeDateCalendar
                        table with data from dbimport.PandasMarketCalendars. If left NULL, the
                        proc will determine the earliest date of data for the target CalendarID 
                        in the dbimport table. Defaults to NULL.
                @EndDate (date, optional): The date to stop updating the dbo.TradeDateCalendar
                        table with data from dbimport.PandasMarketCalendars. If left NULL, the
                        proc will determine the latest date of data for the target CalendarID 
                        in the dbimport table. Defaults to NULL.
                @ZeroDate (date, optional): The date to use as the benchmark '0-date' for the
                        offset columns. This date only has to be a date in the particular calendar.
                        Besides this requirement, this parameter will have no affect on the
                        table or downstream performance. Defaults to 1970-01-01.
                @EndOfWeek (int, optional): What day of the week to define as the "End of the Week"
                        for the purposes of the 'WeekEnd' marker column and 'WeekOffset' column. 
                        Defaults to 7 (Saturday).
                @Debug (bit, optional): If set to 1 (True), the updated calendar resulting from a
                        join of the new dbimport data and existing data will only be returned for
                        the user to view. If set to 0 (False), the data will be inserted into 
                        dbo.TradeDateCalendar and overwrite the existing data. Defaults to 0.
Return:		    New and old data that will be / was inserted into dbo.TradeDateCalendar. This data
                        will be a combination of new dbimport data and existing data in 
                        dbo.TradeDateCalendar where new data does not exist.
Usage:		    EXEC dbo.usp_PandasMarketCalendarsPostImport @CalendarId=1
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
2023-01-10      B Strathman     Created
***********************************************/

CREATE OR ALTER PROCEDURE [dbo].[usp_PandasMarketCalendarsPostImport] (
    @CalendarId int,
    @StartDate date = NULL,
    @EndDate date = NULL,
    @ZeroDate date = '1970-01-01',
    @EndOfWeek int = 7,     -- Sunday=1, Saturday=7
    @Debug bit = 0
) AS
BEGIN
    SET NOCOUNT ON

    -- Create temporary variables for script logic
    DECLARE 
        @NewStartDate date,
        @NewEndDate date,
        @ExistingStartDate date,
        @ExistingEndDate date,
        @str varchar(MAX),
        @UpdateRowCount int

    DECLARE @t TABLE (AsOfDate date)

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
	
	-- Import table prep
    --*********************************************************************************************************************
    -- Delete any old records that no longer need to be retained
    DECLARE @daysToRetain int
    SELECT @daysToRetain = TRY_CONVERT(int, dbo.fn_GetSystemLookupValue('TradeCalendarImport', 'DaysToRetainImportData'))
    PRINT('Deleting records in dbimport.PandasMarketCalendars older than ' + CAST(@daysToRetain AS varchar) + ' days.')

    -- If any records are still 'IN PROGRESS' from the prior run of the post-import proc, mark them as partial
    UPDATE dbimport.PandasMarketCalendars 
    SET RowProcessed = @RP_PARTIAL 
    WHERE RowProcessed = @RP_IN_PROGRESS
    
    -- Handle situations where fn_GetSystemLookupValue did not return a value or the return value cannot be parsed as an int
    DELETE FROM dbimport.PandasMarketCalendars 
    WHERE 
        CreatedDateTime < DATEADD(Day, -1 * ISNULL(@daysToRetain, 0), GETDATE())
        AND @daysToRetain IS NOT NULL 

    -- Mark any inactive rows as errors 
    PRINT('Marking inactive records in dbimport.PandasMarketCalendars as Errors')
    UPDATE dbimport.PandasMarketCalendars  
    SET 
        RowProcessed = @RP_ERROR,
        ModifiedDateTime = GETDATE(),
        ModifiedByUserID = SYSTEM_USER
    WHERE 
        Active = 0 
        AND RowProcessed IS NULL

    -- Check the PK of the target table
    -- Mark rows as errors if any PK columns are NULL or cannot be parsed to their target datatype
    -- Target PK: AsOfDate, CalendarID (already in ant in the dbimport table)
    PRINT('Marking records in dbimport.PandasMarketCalendars with an AsOfDate that cannot be parsed to an integer as Errors')
    UPDATE dbimport.PandasMarketCalendars 
    SET 
        RowProcessed = @RP_ERROR,
        ModifiedDateTime = GETDATE(),
        ModifiedByUserID = SYSTEM_USER
    WHERE 
        RowProcessed IS NULL 
        AND TRY_CONVERT(date, AsOfDate) IS NULL 

    -- Mark rows as duplicates if there are newer records with the same PK
    PRINT('Marking old, duplicate records in dbimport.PandasMarketCalendars as duplicates for CalendarID=' + CAST(@CalendarId AS varchar))
    ;WITH cteLatestUpdate AS (
        SELECT 
            MAX(RowID) AS MaxRowId,
            AsOfDate 
        FROM 
            dbimport.PandasMarketCalendars
        WHERE 
            CalendarID = @CalendarId
            AND RowProcessed IS NULL 
        GROUP BY 
            AsOfDate
    )

    UPDATE t 
    SET 
        RowProcessed = @RP_DUPLICATE,
        ModifiedDateTime = GETDATE(),
        ModifiedByUserID = SYSTEM_USER
    FROM 
        dbimport.PandasMarketCalendars t
        INNER JOIN cteLatestUpdate c 
            ON t.AsOfDate = c.AsOfDate 
    WHERE 
        CalendarID = @CalendarId
        AND t.RowProcessed IS NULL 
        AND t.RowID <> c.MaxRowId


    -- Now that the dbimport table is prepped, determine the other parameters for the script
    --************************************************************************************************************
    -- Determine values for @NewStartDate and @NewEndDate from the dbimport table
    SELECT 
        @NewStartDate = MIN(AsOfDate),
        @NewEndDate = MAX(AsOfDate)
    FROM 
        dbimport.PandasMarketCalendars 
    WHERE 
        RowProcessed IS NULL
        AND CalendarID = @CalendarId

    -- If there is no active data in the dbimport table that needs to be process, the @NewStartDate and @NewEndDate
    -- parameters will be NULL. If this is the case, print an error to the user and exit the procedure.
    IF ((@NewStartDate IS NULL) OR (@NewEndDate IS NULL))
    BEGIN 
        PRINT 'No active data in dbimport.PandasMarketCalendars for CalendarID=' + CAST(@CalendarId AS varchar) + 
                '. No data to move - exiting procedure.'
        GOTO exitProc
    END

    -- If the user didn't provide @StartDate or @EndDate parameters, populate those now. 
    -- If the user did provide @StartDate or @EndDate parameters validate them now - ensure they are bounded by the new data
    SELECT @StartDate = ISNULL(@StartDate, @NewStartDate) 
    IF (@StartDate < @NewStartDate) 
    BEGIN 
        PRINT 'Value error: the provided @StartDate parameter is prior to the start of the new data in dbimport.PandasMarketCalendars' + 
                ' for CalendarID=' + CAST(@CalendarId AS varchar) + '. Updating the @StartDate parameter to the start of the new data.'
        
        SELECT @StartDate = @NewStartDate
    END 

    SELECT @EndDate = ISNULL(@EndDate, @NewEndDate) 
    IF (@EndDate > @NewEndDate) 
    BEGIN 
        PRINT 'Value error: the provided @EndDate parameter is after the end of the new data in dbimport.PandasMarketCalendars' + 
                ' for CalendarID=' + CAST(@CalendarId AS varchar) + '. Updating the @EndDate parameter to the end of the new data.'
        
        SELECT @EndDate = @NewEndDate
    END 

    -- Determine values for the overall Start and End dates between both the dbimport and target tables 
    -- If no data exists for this calendar yet, NULLs will be returned, which need to be handled
    SELECT 
        @ExistingStartDate = MIN(AsOfDate),
        @ExistingEndDate = MAX(AsOfDate)
    FROM 
        dbo.TradeDateCalendar 
    WHERE 
        Active = 1 
        AND CalendarID = @CalendarId 

    SELECT @str = 'Updating dbo.TradeDateCalendar where CalendarID = ' + CAST(@CalendarId AS varchar) + ' between '
    SELECT @str = @str + CAST(@StartDate AS varchar) + ' and ' + CAST(@EndDate AS varchar)
    PRINT(@str)

    -- Build a calendar between the min Start date and max End dates with every single day (not just trade dates)
    --************************************************************************************************************
    -- Seed the calendar first with data already in dbo.TradeDateCalendars as the recursive CTE method to generate
    -- a complete calendar can take quite a bit of time to generate.
    PRINT 'Creating a calendar including all calendar days.'

    INSERT INTO @t (AsOfDate) 
    SELECT AsOfDate 
    FROM dbo.TradeDateCalendar 
    WHERE CalendarID = @CalendarId;

    -- Pad the data from the dbo.TradeDateCalendar with new, recursively generated date data 
    -- If either of the @ExistingStartDate or @ExistingEndDate values are NULL, there is no data in dbo.TradeDateCalendar
    -- for this trade calendar - generate the entire data set using the recursive CTE method.
    IF ((@ExistingStartDate IS NULL) OR (@ExistingEndDate IS NULL))
    BEGIN 
        PRINT 'New calendar - no existing data for CalendarID=' + CAST(@CalendarId AS varchar) + 
                '. Creating new calendar base data between ' + 
                CAST(@StartDate AS varchar) + ' and ' + CAST(@EndDate AS varchar);

        WITH cteCalendar(n) AS (
            SELECT 0 UNION ALL SELECT n + 1 FROM cteCalendar
            WHERE n < DATEDIFF(DAY, @StartDate, @EndDate)
        )
        ,cteAllDates(AsOfDate) AS (
            SELECT DATEADD(DAY, n, @StartDate) FROM cteCalendar
        )

        INSERT INTO @t (AsOfDate)
        SELECT AsOfDate 
        FROM cteAllDates 
        OPTION (MAXRECURSION 0);
    END

    -- If the new data extends earlier than the existing data, pad the start date side of the table
    IF (@StartDate < @ExistingStartDate)
    BEGIN 
        PRINT 'Inserting earlier data - padding calendar data for CalendarID=' + CAST(@CalendarId AS varchar) + 
                ' between ' + CAST(@StartDate AS varchar) + ' and ' + CAST(@ExistingStartDate AS varchar);

        WITH cteCalendar(n) AS (
            SELECT 0 UNION ALL SELECT n + 1 FROM cteCalendar
            WHERE n < DATEDIFF(DAY, @StartDate, DATEADD(DAY, -1, @ExistingStartDate))
        )
        ,cteAllDates(AsOfDate) AS (
            SELECT DATEADD(DAY, n, @StartDate) FROM cteCalendar
        )

        INSERT INTO @t (AsOfDate)
        SELECT AsOfDate 
        FROM cteAllDates 
        OPTION (MAXRECURSION 0);
    END

    -- If the new data extends later than the existing data, pad the end date side of the table
    IF (@EndDate > @ExistingEndDate)
    BEGIN 
        PRINT 'Inserting later data - padding calendar data for CalendarID=' + CAST(@CalendarId AS varchar) + 
                ' between ' + CAST(@ExistingEndDate AS varchar) + ' and ' + CAST(@EndDate AS varchar);

        WITH cteCalendar(n) AS (
            SELECT 0 UNION ALL SELECT n + 1 FROM cteCalendar
            WHERE n < DATEDIFF(DAY, DATEADD(DAY, 1, @ExistingEndDate), @EndDate)
        )
        ,cteAllDates(AsOfDate) AS (
            SELECT DATEADD(DAY, n, DATEADD(DAY, 1, @ExistingEndDate)) FROM cteCalendar
        )

        INSERT INTO @t (AsOfDate)
        SELECT AsOfDate 
        FROM cteAllDates 
        OPTION (MAXRECURSION 0);
    END

    -- Get the trade day data
    --************************************************************************************************************
    -- Preferentially take from the new data
    -- Prepare the market trading calendar
    ;WITH cteMarketDates AS (
        -- Get new data between the @StartDate and @EndDate
        SELECT 
            AsOfDate,
            MarketOpenET,
            MarketCloseET,
            1 AS TradeDay
        FROM 
            dbimport.PandasMarketCalendars
        WHERE 
            RowProcessed IS NULL
            AND CalendarID = @CalendarId
            AND AsOfDate BETWEEN @StartDate AND @EndDate 

        UNION

        -- Get existing data where not between @StartDate and @EndDate
        SELECT 
            AsOfDate,
            MarketOpenET AS MarketOpen,
            MarketCloseET AS MarketClose,
            1 AS TradeDate
        FROM 
            dbo.TradeDateCalendar 
        WHERE 
            TradeDay = 1
            AND CalendarID = @CalendarId 
            AND NOT AsOfDate BETWEEN @StartDate AND @EndDate
    )

    -- Generate the base of the market calendar
    SELECT 
        t.AsOfDate,
        @CalendarId AS CalendarID, 
        LEAD(m.AsOfDate) OVER (ORDER BY m.AsOfDate) NextBusDay,
        m.MarketOpenET,
        m.MarketCloseET,
        ISNULL(TradeDay, 0) AS TradeDay,
        0 AS WeekEnd,
        0 AS MonthEnd,
        0 AS QuarterEnd,
        0 AS YearEnd,
        0 AS DayOffset,
        0 AS WeekOffset,
        0 AS MonthOffset,
        0 AS QuarterOffset,
        0 AS YearOffset
    INTO #temp
    FROM 
        @t t
        LEFT JOIN cteMarketDates m 
            ON t.AsOfDate = m.AsOfDate
    ORDER BY 
        t.AsOfDate

    -- Downfill the [NextBusDay] column
    ;WITH cteNextBusDayGroups AS (
        SELECT 
            AsOfDate,
            COUNT(NextBusDay) OVER (ORDER BY AsOfDate DESC) AS _grp
        FROM 
            #temp
    )
    ,cteLatestDates AS (
        SELECT 
            AsOfDate,
            _grp,
            FIRST_VALUE(AsOfDate) OVER (PARTITION BY _grp ORDER BY AsOfDate DESC) AS NextBusDay
        FROM 
            cteNextBusDayGroups
    )

    UPDATE t 
    SET t.NextBusDay = ISNULL(t.NextBusDay, ld.NextBusDay) 
    FROM 
        #temp t 
        LEFT JOIN cteLatestDates ld 
            ON t.AsOfDate = ld.AsOfDate


    -- Update the offset and end of period columns
    --************************************************************************************************************
    -- * It was decided to set the WeekEnd market column on the last trading date of the week becuase it is easier
    --      to find a pre-set day of the week (the Friday of each trading week) from the last trading date of the 
    --      week than the reverse (finding the last trade day of the week from the Friday of the week). 
    --      For example, to find the last Friday of each trade week:
    --          SELECT Trade_Week_Fridays = DATEADD(day, (6 - DATEPART(dw, AsOfDate)), AsOfDate)
    --          FROM dbo.TradeDateCalendar 
    --          WHERE WeekEnd = 1

    -- Populate the MonthEnd, QuarterEnd, and YearEnd columns
    -- **End of Week markers are "done in reverse". First the WeekOffset is calculated then the last trade day in each week is found.**
    UPDATE #temp SET MonthEnd = 1   WHERE TradeDay = 1 AND MONTH(AsOfDate) <> MONTH(NextBusDay)
    UPDATE #temp SET QuarterEnd = 1 WHERE MonthEnd = 1 AND MONTH(AsOfDate) IN (3, 6, 9, 12)
    UPDATE #temp SET YearEnd = 1    WHERE QuarterEnd = 1 AND MONTH(AsOfDate) = 12

    -- Populate the DayOffset column using a window function on both the pre- and post- @ZeroDate portions of the table
    -- Update all the offset columns
    -- Calculate the day offsets from the beginning of time
    ;WITH cteDayOffsets AS (
        SELECT 
            AsOfDate,
            SUM(CAST(TradeDay AS int)) OVER (ORDER BY AsOfDate) AS DayOffset
        FROM 
            #temp 
    )

    UPDATE cal 
    SET cal.DayOffset = c.DayOffset 
    FROM 
        #temp cal 
        LEFT JOIN cteDayOffsets c 
            ON cal.AsOfDate = c.AsOfDate 

    -- Re-zero the day offsets to be on the zero date
    DECLARE @DayZeroOffset int
    SELECT @DayZeroOffset = DayOffset 
    FROM #temp
    WHERE AsOfDate = @ZeroDate  

    UPDATE #temp
    SET DayOffset = DayOffset - @DayZeroOffset

    -- Populate the WeekOffset column and the WeekEnd column
    -- First, find the end of the 0th week
    DECLARE @EndOfWeekZero date
    SELECT @EndOfWeekZero = AsOfDate
    FROM #temp 
    WHERE 
        AsOfDate >= @ZeroDate 
        AND AsOfDate < DATEADD(day, 7, @ZeroDate) 
        AND DATEPART(dw, AsOfDate) = @EndOfWeek

    -- Calculate the number of weeks 7 day perods between the end of the 0th week and each other day in the table
    UPDATE #temp
    SET WeekOffset = CEILING(DATEDIFF(day, @EndOfWeekZero, AsOfDate) / 7.0)

    -- Finally, grouping by the WeekOffset column, find the last trade date within each week
    ;WITH cteLastDayOfWeeks AS (
        SELECT 
            WeekOffset,
            LastWeekDay = MAX(AsOfDate)
        FROM #temp
        WHERE TradeDay = 1
        GROUP BY WeekOffset 
    )

    UPDATE cal 
    SET cal.WeekEnd = 1 
    FROM 
        #temp cal 
        INNER JOIN cteLastDayOfWeeks c
            ON cal.WeekOffset = c.WeekOffset 
            AND cal.AsOfDate = c.LastWeekDay 

    -- Update the Month, Quarter, and Year Offset columns using the end of calendar Months, Quarters, and Years
    UPDATE #temp
    SET 
        MonthOffset = DATEDIFF(month, @ZeroDate, AsOfDate),
        QuarterOffset = DATEDIFF(quarter, @ZeroDate, AsOfDate),
        YearOffset = DATEDIFF(year, @ZeroDate, AsOfDate)

    PRINT 'Updated calendar data in #temp table.'

    -- If the user just wants to debug the data import process, return the #temp data and exit the proc
    IF (@Debug = 1) 
    BEGIN 
        PRINT 'Debug mode - diplaying data update for dbo.TradeDateCalendar where CalendarID=' + CAST(@CalendarId AS varchar) + 
                '. '
        SELECT * FROM #temp ORDER BY AsOfDate
        GOTO exitProc
    END

    -- Temp table has all required and updated data - merge it with the dbo.TradeDateCalendar target table 
    --************************************************************************************************************
    BEGIN TRY
        BEGIN TRANSACTION;
            -- Mark all the dbimport records that were used to generate the #temp data as being processed
            UPDATE dbimport.PandasMarketCalendars  
            SET RowProcessed = @RP_IN_PROGRESS 
            WHERE 
                RowProcessed IS NULL
                AND CalendarID = @CalendarId
                AND AsOfDate BETWEEN @StartDate AND @EndDate 

            SELECT @UpdateRowCount = COUNT(*) 
            FROM dbimport.PandasMarketCalendars 
            WHERE RowProcessed = @RP_IN_PROGRESS AND CalendarID = @CalendarId

            -- Merge the dbimport table and the target table
            -- After the data scrubbing above, all the "in progress" dbimport records will have a unique, parsable PK
            PRINT 'Merging dbimport.PandasMarketCalendars with #temp table'
            ;MERGE dbo.TradeDateCalendar t 
            USING #temp s 
                ON t.AsOfDate = s.AsOfDate
                AND t.CalendarID = s.CalendarID
            
            -- Update pre-existing Accounts
            WHEN MATCHED THEN UPDATE SET 
                    AsOfDate            = s.AsOfDate,
                    NextBusDay          = s.NextBusDay,
                    MarketOpenET        = s.MarketOpenET,
                    MarketCloseET       = s.MarketCloseET,
                    TradeDay            = s.TradeDay,
                    WeekEnd             = s.WeekEnd,
                    MonthEnd            = s.MonthEnd,
                    QuarterEnd          = s.QuarterEnd,
                    YearEnd             = s.YearEnd,
                    DayOffset           = s.DayOffset,
                    WeekOffset          = s.WeekOffset, 
                    MonthOffset         = s.MonthOffset,
                    QuarterOffset       = s.QuarterOffset,
                    YearOffset          = s.YearOffset,
                    CalendarID          = s.CalendarID,
                    ModifiedDateTime    = GETDATE(),
                    ModifiedByUserID    = SYSTEM_USER 

            -- Insert new accounts into the target table
            WHEN NOT MATCHED BY TARGET THEN 
                    INSERT (AsOfDate, NextBusDay, MarketOpenET, MarketCloseET, TradeDay, 
                            WeekEnd, MonthEnd, QuarterEnd, YearEnd, 
                            DayOffset, WeekOffset, MonthOffset, QuarterOffset, YearOffset, 
                            CalendarID, InsertedIntoThisTable)
                    VALUES (s.AsOfDate, s.NextBusDay, s.MarketOpenET, s.MarketCloseET, s.TradeDay, 
                            s.WeekEnd, s.MonthEnd, s.QuarterEnd, s.YearEnd, 
                            s.DayOffset, s.WeekOffset, s.MonthOffset, s.QuarterOffset, s.YearOffset, 
                            s.CalendarID, GETDATE())

            -- Don't do anything if date was not found in the #temp table
            -- Not sure how this would even happen as #temp was constructed to include all existing dates in both 
            -- the dbimport.PandasMarketCalendars table and the dbo.TradeDateCalendar tables.
            -- WHEN NOT MATCHED BY SOURCE THEN UPDATE SET 
            ;

            -- Update the rows in the dbimport table marking them as complete and processed
            UPDATE 
                dbimport.PandasMarketCalendars 
            SET 
                RowProcessed = @RP_COMPLETE,
                ModifiedDateTime = GETDATE(),
                ModifiedByUserID = SYSTEM_USER 
            WHERE 
                RowProcessed = @RP_IN_PROGRESS

            PRINT 'Merge transaction between the temp table and dbo.TradeDateCalendar completed without error - committing'
            PRINT 'Inserted or updated ' + CAST(@UpdateRowCount AS varchar) + 
                    ' trade dates in dbo.TradeDateCalendar for CalendarID=' + CAST(@CalendarId AS varchar)

commitProc:
        COMMIT TRANSACTION;

        -- Select the #temp table to ensure the return is the same between the debug=0 and debug=1 procedures
        SELECT * FROM #temp ORDER BY AsOfDate

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