USE LidoIM;
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************
Name:		    schema.usp_StoredProcName
Author:	        Last, F
Organization:	Lido Advisors - Investment Management
Create date:    yyyy-mm-dd
Description:	
Parameters:	    @param1 (datatype): description
                @param2 (datatype): description
Return:		    
Usage:		    
Repo:		    Database\LidoIM\StoredProcedures

Revisions
Date            Developer       Change
yyyy-mm-dd      F Last          Created
***********************************************/

CREATE OR ALTER PROCEDURE [dbo].[usp_StoredProcName] (
    @param1 datatype = DEFAULT,
    @param2 datatype = DEFAULT
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
        BEGIN TRANSACTION;

commitProc:
        COMMIT TRANSACTION;

        -- Put anything here that needs to execute before exiting the proc 
        -- after a successful completeion

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
