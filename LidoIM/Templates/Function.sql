USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    schema.fn_FunctionName
Author:	        Last, F
Organization:	Lido Advisors - Investment Management
Create date:    yyyy-mm-dd
Description:	
Parameters:	    @param1 (datatype): description
                @param2 (datatype): description
Return:		    
Usage:		    
Repo:		    Database\LidoIM\Functions

Revisions
Date            Developer       Change
yyyy-mm-dd      F Last          Created
***********************************************/

CREATE OR ALTER FUNCTION [dbo].[fn_FunctionName] (
    @param1 datatype = DEFAULT,
    @param2 datatype = DEFAULT
) RETURNS ReturnType AS
BEGIN

    DECLARE @Result bit = 0


	RETURN @Result
END
GO
