
DECLARE @strRootPath varchar(50) = 'C:\Users\bstrathman\Database_Backups\'
DECLARE @BackupFile varchar(100)
DECLARE @strDB varchar(25) = db_name()

SELECT @BackupFile = 
		@strRootPath
			+ db_name() + '_'
			+ CONVERT(varchar(8), GetDate(), 112)	-- yyyymmdd
			+ '.BAK'

BACKUP DATABASE @strDB TO  DISK =@BackupFile WITH RETAINDAYS = 10, NAME = N'LidoIM_DATA-Full Database Backup', STATS = 10
