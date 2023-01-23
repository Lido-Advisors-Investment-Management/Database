
-- Unit tests for LidoIM.dbo.fn_TradeDateAdd

-- Create a results table
DECLARE @results TABLE (iDatePart varchar(10), iShiftSize int, iReferenceDate date, iCalendarId int, iAdjustStartDate int, expectedResult date, returnDate date, testPass bit)

-- Create all the tests and insert them into the results table
INSERT INTO @results (iDatePart, iShiftSize, iReferenceDate, iCalendarId, iAdjustStartDate, expectedResult) 
VALUES 
    -- Test each of the allowable datePart values
    ('Day',     1, '2022-11-21', 1, 0, '2022-11-22'),
    ('D',       1, '2022-11-21', 1, 0, '2022-11-22'),
    ('Week',    1, '2022-11-21', 1, 0, '2022-12-02'),
    ('W',       1, '2022-11-21', 1, 0, '2022-12-02'),
    ('Month',   1, '2022-11-21', 1, 0, '2022-12-30'),
    ('M',       1, '2022-11-21', 1, 0, '2022-12-30'),
    ('Quarter', 1, '2022-11-21', 1, 0, '2023-03-31'),
    ('Q',       1, '2022-11-21', 1, 0, '2023-03-31'),
    ('Year',    1, '2022-11-21', 1, 0, '2023-12-29'),
    ('Y',       1, '2022-11-21', 1, 0, '2023-12-29'),

    ('dAy',     1, '2022-11-21', 1, 0, '2022-11-22'),   -- Ensure no case sensitivity
    ('Day ',    1, '2022-11-21', 1, 0, '2022-11-22'),   -- Varchar trims trailing spaces

    -- Ensure bad datePart values return NULL
    ('asdf',    1, '2022-11-21', 1, 0, NULL),
    ('Days',    1, '2022-11-21', 1, 0, NULL),
    (' Day',    1, '2022-11-21', 1, 0, NULL),
    ('D ay',    1, '2022-11-21', 1, 0, NULL),
    ('',        1, '2022-11-21', 1, 0, NULL),
    (NULL,      1, '2022-11-21', 1, 0, NULL),

    -- A significant use for this function is finding the last or next trade date from some reference date 
    -- or ensuring that the passed date was (or will be a trade date). Test these scenarios specifically.
    ('D', 0, '2022-11-19', 1, -1, '2022-11-18'),        -- Find last trade date from a weekend
    ('D', 0, '2022-11-19', 1, 1, '2022-11-21'),         -- Find next trade date from a weekend
    ('D', 0, '2022-11-24', 1, -1, '2022-11-23'),        -- Find last trade date from a holiday (Thanksgiving)
    ('D', 0, '2022-11-24', 1, 1, '2022-11-25'),         -- Find next trade date from a holiday (Thanksgiving)
    ('D', 0, '2022-11-22', 1, -1, '2022-11-22'),        -- Ensure trade days aren't adjusted
    ('D', 0, '2022-11-22', 1, 1, '2022-11-22'),         -- Ensure trade days aren't adjusted

    -- General tests
    ('D', 10, '2022-11-19', 1, 0, '2022-12-05'),        -- Shift forward - remember thanksgiving
    ('D', -10, '2022-11-19', 1, 0, '2022-11-07'),       -- Shift back
    ('D', -10, '2022-11-19', 1, -1, '2022-11-04'),      -- Shift back from shifted date
    ('W', 5, '2022-11-19', 1, 0, '2022-12-23'),         -- Shift forward - week
    ('W', -5, '2022-11-19', 1, 0, '2022-10-14'),        -- Shift back - week
    ('M', 10, '2022-11-21', 1, 0, '2023-09-29'),        -- Shift forward - month
    ('M', -10, '2022-11-21', 1, 0, '2022-01-31'),       -- Shift back - month
    ('Q', 4, '2022-11-21', 1, 0, '2023-12-29'),         -- Shift forward - quarter
    ('Q', -4, '2022-11-21', 1, 0, '2021-12-31'),        -- Shift back - quarter
    ('Y', 2, '2022-11-21', 1, 0, '2024-12-31'),         -- Shift forward - year
    ('Y', -2, '2022-11-21', 1, 0, '2020-12-31'),        -- Shift back - year

    -- Test the @adjustStartDate parameter using Friday-Monday periods 2021-12-31 to 2022-01-03 and 2022-04-29 to 2022-05-30
    ('D', 0, '2022-04-30', 1,    0,     '2022-04-29'),      -- Shifts to the last completed trade date
    ('D', 0, '2022-04-30', 1,    1,     '2022-05-02'),      -- Adjust forward
    ('D', 0, '2022-04-30', 1,    -1,    '2022-04-29'),      -- Should be adjust back
    ('D', 0, '2022-01-01', 1,    0,     '2021-12-31'),      -- Shouldn't be adjusted
    ('D', 0, '2022-01-01', 1,    1,     '2022-01-03'),      -- Should be adjust forward
    ('D', 0, '2022-01-01', 1,    -1,    '2021-12-31'),      -- Should be adjust back
    -- Week - the trade week ends on the last trade date of the week (not on a pre-set day of the week)
    ('W', 1, '2022-04-30', 1,    0,     '2022-05-06'),      -- Saturday input date is included in prior week
    ('W', 1, '2022-04-30', 1,    1,     '2022-05-13'),      -- Start date will be adjusted forward to the next trade week SOW and then shifted
    ('W', 1, '2022-04-30', 1,    -1,    '2022-05-06'),      -- Saturday input date is included in prior week - won't have any impact
    ('W', -1, '2022-05-01', 1,   0,     '2022-04-29'),      -- Sunday input date is included in following week
    ('W', -1, '2022-05-01', 1,   1,     '2022-04-29'),      -- Sunday input date is included in following week - won't have any impact
    ('W', -1, '2022-05-01', 1,   -1,    '2022-04-22'),      -- Start date will be adjusted back to the prior trade week EOW and then shifted
    -- Test a friday holiday - Good firday was on 2022-04-15
    ('W', 0, '2022-04-15', 1,    0,     '2022-04-14'),      -- Friday is included in the next trade week - Thrusday was EOW
    ('W', 0, '2022-04-15', 1,    1,     '2022-04-22'),      -- Adjusted forward and returns the same week
    ('W', 0, '2022-04-15', 1,    -1,    '2022-04-14'),      -- Adjusts start date back to Thrusday before shifting
    -- Month tests
    ('M', 1, '2022-04-30', 1,    0,     '2022-05-31'),      -- No adjustment made - returns EOM trade date of next calendar month
    ('M', 1, '2022-04-30', 1,    1,     '2022-06-30'),      -- Adjusts start date forward to 2022-05-02 before shifting one calendar month
    ('M', 1, '2022-04-30', 1,    -1,    '2022-05-31'),      -- Adjusts start date back to 2022-04-29 but has no effect
    ('M', 1, '2022-05-01', 1,    0,     '2022-06-30'),      -- No adjustment made - returns EOM trade date of next calendar month
    ('M', 1, '2022-05-01', 1,    1,     '2022-06-30'),      -- Adjusts start date forward to 2022-05-02 but has no effect
    ('M', 1, '2022-05-01', 1,    -1,    '2022-05-31'),      -- Adjusts start date back to 2022-04-29 before shifting one calendar month
    -- Quarter tests
    ('Q', 1, '2022-01-01', 1,    0,     '2022-06-30'),      -- No adjustment made - returns EOQ trade date of next calendar quarter
    ('Q', 1, '2022-01-01', 1,    1,     '2022-06-30'),      -- Adjusts start date forward to 2022-01-03 but has no effect
    ('Q', 1, '2022-01-01', 1,    -1,    '2022-03-31'),      -- Adjusts start date back to 2021-12-31 before shifting the one calendar quarter
    -- Year tests
    ('Y', 0, '2022-01-01', 1,    0,     '2022-12-30'),      -- No adjustment made - returns EOQ trade date of next calendar quarter
    ('Y', 0, '2022-01-01', 1,    1,     '2022-12-30'),      -- Adjusts start date forward to 2022-01-03 but has no effect
    ('Y', 0, '2022-01-01', 1,    -1,    '2021-12-31'),      -- Adjusts start date back to 2021-12-31 before shifting the one calendar quarter

    -- Ensure bad @adjustStartDate values return NULL
    ('Day', 1, '2022-11-21', 1,     0,      '2022-11-22'),
    ('Day', 1, '2022-11-21', 1,     -2,     NULL),
    ('Day', 1, '2022-11-21', 1,     2,      NULL),

    -- Ensure bad values for @shiftSize, @referenceDate, or @calendarId also return NULL
    ('Day', 1, '1900-01-01', 1, 0, NULL),       -- referenceDate is before the start of the calendar
    ('Day', 1, '2100-01-01', 1, 0, NULL),       -- referenceDate is after the end of the calendar
    ('Day', 1, '2022-11-21', 999999, 0, NULL),  -- shiftSize is too large - pushes the returnDate off the end of the calendar
    ('Day', 1, '2022-11-21', -999999, 0, NULL), -- shiftSize is too large - pushes the returnDate off the start of the calendar
    ('Day', 1, '1900-01-01', 0, 0, NULL)        -- Calendar ID does not exist


-- Run all the tests and display the results
UPDATE @results SET returnDate = dbo.fn_TradeDateAdd(iDatePart, iShiftSize, iReferenceDate, iCalendarId, iAdjustStartDate)

UPDATE @results SET testPass = CASE 
    WHEN returnDate = expectedResult THEN 1 
    WHEN returnDate IS NULL AND expectedResult IS NULL THEN 1
    ELSE 0 END

SELECT * FROM @results ORDER BY testPass

DECLARE @testCount int = (SELECT COUNT(*) FROM @results)
DECLARE @passCount int = (SELECT COUNT(*) FROM @results WHERE testPass = 1)
DECLARE @failCount int = (SELECT COUNT(*) FROM @results WHERE testPass = 0)
DECLARE @successRate float = (SELECT CAST(@passCount AS float) / CAST(@testCount AS float))

PRINT ''
PRINT '  UNIT TEST RESULTS  '
PRINT '---------------------'
PRINT 'Tests passed: ' + CAST(@passCount AS varchar) + ' / ' + CAST(@testCount AS varchar)
PRINT 'Tests failed: ' + CAST(@failCount AS varchar) + ' / ' + CAST(@testCount AS varchar)
PRINT 'Success rate: ' + CAST(@successRate AS varchar)
