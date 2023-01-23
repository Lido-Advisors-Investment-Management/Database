USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    dbo.fn_GetSystemLookupValue
Author:	        Strathman, B
Organization:	Lido Advisors - Investment Management
Create date:    2023-01-10
Description:	Wrapper function to get the LookupValue associated with the unique combination of passed 
                        ProcessName and LookupName (PK of dbo.SystemLookup table). Although a function is
                        not necessary for such a simple select statement, abstracting the logic allows for
                        the underlying lookup value infrastructure to change without impacting the 
                        procedures that need access to the lookup values.
Parameters:	    @processName (varchar): ProcessName of the desired lookup value - reference dbo.SystemLookup
                @lookupName (varchar): LookupName of the desired lookup value - reference dbo.SystemLookup
Return:		    varchar(50): The value associated with the passed @processName and @lookupName 
                        Returns NULL if the ProcessName-LookupName combination does not exist.
Usage:		    SELECT @lookupValue = dbo.fn_GetSystemLookupValue('AddeparRecon', 'DaysToRetainAccountsImport')
Repo:		    Database\LidoIM\Functions

Revisions
Date            Developer       Change
2023-01-10      B Strathman     Created
***********************************************/

CREATE OR ALTER FUNCTION [dbo].[fn_GetSystemLookupValue] (
    @processName varchar(50),
    @lookupName  varchar(50)
) RETURNS varchar(50) AS
BEGIN

    DECLARE @Result varchar(50) = NULL;

    SELECT @Result = LookupValue 
    FROM dbo.SystemLookup 
    WHERE 
        ProcessName = @processName 
        AND LookupName = @lookupName

	RETURN @Result
END
GO
