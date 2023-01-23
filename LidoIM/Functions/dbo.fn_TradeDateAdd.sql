USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    fn_TradeDateAdd
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2022-11-25
Description:	Similar to the built-in DATEADD(datePart, number, date) function that adds a number of date parts (days, months, etc.)
                    to the passed in reference date, this function will similarly shift a date constrained by a trade clendar.
                    This function can reference any trade calendar in LidoIM.dbo.TradeDateCalendars (see LidoIM.dbo.PandasCalendarCode 
                    table for details of each calendar ID). This function was designed to work similarly to DATEADD and the first 
                    three parameters are the same.
Parameters:	    @datePart (varchar): the part of the date the increment or decrement. Date parts greater than a day will
                                shift the @referenceDate by CALENDAR date parts and will then return the last trade date 
                                of the final Month, Quarter, or Year. 
                        'Day' or 'D': Shift the @referenceDate by the passed number of TRADE DAYS
                        'Week' or 'W': Shift by CALENDAR WEEKS and return the last trade day in the the resulting week
                        'Month' or 'M': Shift by CALENDAR MONTHS and return the last trade day in the the resulting month
                        'Quarter' or 'Q': Shift by CALENDAR QUARTERS and return the last trade day in the the resulting quarter
                        'Year' or 'Y': Shift by CALENDAR YEARS and return the last trade day in the the resulting year
                @shiftSize (int): The number of time periods (specified in the @datePart parameter) to shift. 
                                    Use negative numbers to shift back in time. Positive numbers to shift forward. 
                @referenceDate (date): The date to begin the shift from.
                @calendarId (int): The ID of the trade calendar to use for the shift. From LidoIM.dbo.PandarsCalendarCode
                @adjustStartDate (int - Defualt = -1): 
                                **This parameter only matters if the passed @referenceDate is not a trade date 
                                Adjust the start date to the closest trade date BEFORE the specified shift if the passed @referenceDate
                                is not already a trade date. This can be especially impactful when shifting by date parts larger than 
                                a day. For example, consider a calendar month end that occurs over a weeekend (EOM April-2022):
                                    Friday 2022-04-29, Saturday 2022-04-30, Sunday 2022-05-01, Monday 2022-05-02
                                    If the call is to shift by a passed number of months and Saturday 2022-04-30 or Sunday 2022-05-01
                                    is passed as the reference date, using the unadjusted reference date, the reference date shifted 
                                    BACK to the last trade date, or the reference date shifted FORWARD to the next trading day can all 
                                    give different results.
                        0: DO NOT alter the @referenceDate before shifting even if it is not a trade date
                        -1: Update the @referenceDate by shifting it BACK to the last trade date before shifting it
                        1: Update the @referenceDate by shifting it FORWARD to the next trade date before shifting it
Return:		    date: The shifted trade date 
Usage:          dbo.fn_TradeDate(@datePart, @shiftSize, @referenceDate, @calendarId, @adjustStartDate)
                dbo.fn_TradeDateAdd('Day', 100, '2022-11-23', 1, 0)     - Find the date 100 trade days after '2022-11-23'
                dbo.fn_TradeDateAdd('D', 100, '2022-11-23', 1, 0)       - Find the date 100 trade days after '2022-11-23'
                dbo.fn_TradeDateAdd('D', 100, GETDATE(), 1, -1)         - Find the date 100 trade days after the last completed trade date
                dbo.fn_TradeDateAdd('Day', -100, '2022-11-23', 1, 0)    - Find the date 100 trade days before '2022-11-23'
                dbo.fn_TradeDateAdd('Day', 0, '2022-11-23', 1, -1)      - Find the LAST trade day - returns '2022-11-23' since it was a trade day
                dbo.fn_TradeDateAdd('Day', 0, '2022-11-20', 1, -1)      - Find the LAST trade day - returns '2022-11-18' since the 20th was a Sunday
                dbo.fn_TradeDateAdd('Day', 0, '2022-11-20', 1, 1)       - Find the NEXT trade day - returns '2022-11-21' since the 20th was a Sunday
                dbo.fn_TradeDateAdd('Week', 13, '2022-11-23', 1, 1)     - Find the last trade date of the week 13 weeks after '2022-11-23'
                dbo.fn_TradeDateAdd('Month', 5, '2022-11-23', 1, -1)    - Find the last trade date of the month 5 months after '2022-11-23'
                dbo.fn_TradeDateAdd('Month', 1, '2022-04-30', 1, -1)    - Find the last trade date of the month 1 month after '2022-04-30' - returns '2022-05-31'
                dbo.fn_TradeDateAdd('Month', 1, '2022-04-30', 1, 0)     - Find the last trade date of the month 1 month after '2022-04-30' - returns '2022-05-31'
                dbo.fn_TradeDateAdd('Month', 1, '2022-04-30', 1, 1)     - Find the last trade date of the month 1 month after '2022-04-30' - returns '2022-06-30' 
                                                                            since '2022-04-30' is a Saturday, it gets updated to '2022-05-02' before the shift occurs
                dbo.fn_TradeDateAdd('Month', 1, '2022-05-01', 1, -1)    - Find the last trade date of the month 1 month after '2022-05-01' - returns '2022-05-31' 
                                                                            since '2022-05-01' is a Sunday, it gets updated to '2022-04-29' before the shift occurs
                dbo.fn_TradeDateAdd('Month', 1, '2022-05-01', 1, 0)     - Find the last trade date of the month 1 month after '2022-05-01' - returns '2022-06-30'
                dbo.fn_TradeDateAdd('Month', 1, '2022-05-01', 1, 1)     - Find the last trade date of the month 1 month after '2022-05-01' - returns '2022-06-30'
                dbo.fn_TradeDateAdd('Quarter', 2, '2022-11-23', 1, 1)   - Find the last trade date of the quarter 2 quarters after '2022-11-23'
                dbo.fn_TradeDateAdd('Year', -1, '2022-01-01', 1, 1)     - Find the last trade date of 2021
Repo:		    Database\LidoIM\Functions

Revisions
Date            Developer       Change
2022-11-25      B Strathman     Created
***********************************************/

CREATE OR ALTER FUNCTION [dbo].[fn_TradeDateAdd] (
    @datePart varchar(10),
    @shiftSize int,
    @referenceDate date,
    @calendarId int,
    @adjustStartDate int = -1
) RETURNS date AS
BEGIN

    DECLARE 
        @basisDate date = @referenceDate,   -- Date to start the shift from
        @basisPosition int,                 -- Position of the @basisDate
        @lDatePart varchar(10),             -- local date part
        @returnDate date                    -- Shifted date to return
    
    ------------------------------------------------------------------------------------------------
    -- Standardize the @datePart parameter to simplify the logic of the function
    SELECT @lDatePart = 
        CASE 
            WHEN @datePart = 'Day' THEN 'D'
            WHEN @datePart = 'Week' THEN 'W'
            WHEN @datePart = 'Month' THEN 'M'
            WHEN @datePart = 'Quarter' THEN 'Q'
            WHEN @datePart = 'Year' THEN 'Y'
            ELSE @datePart
        END

    ------------------------------------------------------------------------------------------------
    -- Parameter validation
    -- If @shiftSize, @calendarId, or @adjustStartDate are invalid, the function will natually reutrn NULL
    -- Validate @datePart and @adjustStartDate and return NULL if they are not allowable values.
    IF NOT (@lDatePart = 'D' OR @lDatePart = 'W' OR @lDatePart = 'M' OR @lDatePart = 'Q' OR @lDatePart = 'Y')
        RETURN NULL

    IF NOT (@adjustStartDate = -1 OR @adjustStartDate = 0 OR @adjustStartDate = 1)
        RETURN NULL
    
    ------------------------------------------------------------------------------------------------
    -- Adjust the start date back (-1) or forward (1) depending on the @adjustStartDate parameter
    IF (@adjustStartDate = -1)
        SELECT TOP 1 @basisDate = AsOfDate 
        FROM dbo.TradeDateCalendar 
        WHERE 
            Active = 1
            AND CalendarID = @calendarId 
            AND TradeDay = 1
            AND AsOfDate <= @referenceDate
        ORDER BY AsOfDate DESC

    IF (@adjustStartDate = 1)
        SELECT TOP 1 @basisDate = AsOfDate 
        FROM dbo.TradeDateCalendar 
        WHERE 
            Active = 1
            AND CalendarID = @calendarId 
            AND TradeDay = 1
            AND AsOfDate >= @referenceDate
        ORDER BY AsOfDate ASC
    
    ------------------------------------------------------------------------------------------------
    -- Find the position of the @basisDate
    SELECT 
        @basisPosition = CASE 
            WHEN @lDatePart = 'D' THEN DayOffset 
            WHEN @lDatePart = 'W' THEN WeekOffset 
            WHEN @lDatePart = 'M' THEN MonthOffset 
            WHEN @lDatePart = 'Q' THEN QuarterOffset 
            WHEN @lDatePart = 'Y' THEN YearOffset 
            ELSE 0
        END
    FROM 
        dbo.TradeDateCalendar 
    WHERE 
        Active = 1
        AND CalendarID = @calendarId 
        AND AsOfDate = @basisDate 

    ------------------------------------------------------------------------------------------------
    -- Find the date corresponding to the shifted @basisPosition
    DECLARE @returnPosition int = @basisPosition + @shiftSize

    -- ** Handle special case **
    -- The DayOffset counter in the dbo.TradeDateCalendar is not incremented on weekends. As a result,
    -- weekend have the same DayOffset as the trade day immediately preceeding them. Because of this
    -- and the logic of this function, when adjusting back in time (negative @shiftStep) by days (@datePart),
    -- the reference date is a weekend, and the @adjustStartDate parameter is 0, the date will be
    -- decremented by one additional trade day.
    -- This special case override does cause the possibly unexpected side affect that the two function calls
    -- below will return the same result. The alternative is to return have the first call return the passed
    -- date but this function should ALWAYS return a trade date. Further, if this is the expected behavior
    -- by the calling function (to return the passed date), no function is needed.
    --      dbo.fn_TradeDateOffset('D',   0,   'yyyy-MM-dd', 1, 0)
    --      dbo.fn_TradeDateOffset('D',   -1,   'yyyy-MM-dd', 1, 0)
    DECLARE @isReferenceDateTradeDay bit 

    SELECT @isReferenceDateTradeDay = TradeDay 
    FROM dbo.TradeDateCalendar 
    WHERE 
        Active = 1
        AND CalendarId = @calendarId 
        AND AsOfDate = @referenceDate
    
    IF (@lDatePart = 'D' AND @shiftSize < 0 AND @isReferenceDateTradeDay = 0 AND @adjustStartDate = 0)
        SELECT @returnPosition = @returnPosition + 1

    -- Instead of breaking this part into 5 different IF-THAN clauses, use
    -- boolean logic in the WHERE clause to filter on the correct columns.
    SELECT 
        @returnDate = AsOfDate
    FROM 
        dbo.TradeDateCalendar 
    WHERE 
        Active = 1
        AND CalendarID = @calendarId 
        -- Only one of these below 5 filters will have any affect based off of the @datePart parameter
        -- For all the date parts that should not be filtered on, the "NOT (@datePart = '' ...)" statement 
        -- will evaluate to TRUE for all records and thus not filtering the table at all.
        AND (NOT (@lDatePart = 'D') OR (TradeDay = 1 AND DayOffset = @returnPosition))
        AND (NOT (@lDatePart = 'W') OR (WeekEnd = 1 AND WeekOffset = @returnPosition))
        AND (NOT (@lDatePart = 'M') OR (MonthEnd = 1 AND MonthOffset = @returnPosition))
        AND (NOT (@lDatePart = 'Q') OR (QuarterEnd = 1 AND QuarterOffset = @returnPosition))
        AND (NOT (@lDatePart = 'Y') OR (YearEnd = 1 AND YearOffset = @returnPosition))

	RETURN @returnDate
END
GO
