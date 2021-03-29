# kix18sync

To provide simple tools to import data into KIX18 by using its REST-API, data sources may be remote DB tables or CSV files.

These scripts are intented to work as external tools accessing KIX only by its REST-API. They can be run on the docker host running KIX, however this scenario is not a generic use case. Keep in mind to give proper configuration of the KIX-REST **Backend** API, that is correct port number if running on the docker host.

These scripts **do not** evaluate your docker setup in environment files in order to run.


## Contents/Structure
- directory `bin`: scripts for data synchronization
- directory `config`: default/sample configuration
- directory `sample`: sample import data (CSV)

## Required Perl Packages

Scripts have been developed using CentOS8 or Ubuntu/Debian as target plattform. Following packages must be installed:

- CentOS/RHEL
```
shell> sudo yum install perl-Config-Simple perl-REST-Client perl-JSON perl-LWP-Protocol-https perl-DBI perl-URI perl-Pod-Usage perl-Getopt-Long perl-Text-CSV
```
- Ubuntu/Debian
```
shell> sudo apt install libconfig-simple-perl librest-client-perl libjson-perl liblwp-protocol-https-perl libdbi-perl liburi-perl perl-doc libgetopt-long-descriptive-perl libtext-csv-perl
```



----
## Manage Roles and Permissions - kix18.ManageRoles.pl

Script `bin/kix18.ManageRoles.pl` retrieves role and permission infomation from a KIX18 by communicating with its REST-API.

The provided `RoleData_Sample.csv` contains default roles and permissions as delivered by KIX. We try to keep this up to date. However, this script collection is mostly a fun side project, so please bear with us if it should lag behind and give us a hind.


### Usage

```
./bin/kix18.ManageRoles.pl --help
./bin/kix18.ManageRoles.pl --config ./config/kix18.ManageRoles.cfg --dir export -d /tmp
./bin/kix18.ManageRoles.pl --config ./config/kix18.ManageRoles.cfg --dir import --f ./sample/RoleData_Sample.csv --verbose 2
```


The script can be used by referring to a configuration and object type only. Any parameter given by command line overwrites values specified in the config file. Use `kix18.DBSync.pl --help` for a detailed parameter listing.


- `dir`: direction (import|export), "export" if not given
- `config`: path to configuration file instead of command line params
- `url`: URL to KIX backend API (e.g. https://t12345-api.kix.cloud)
- `u`: KIX user login
- `p`: KIX user password
- `d`: output directory to which role permissions are written (if direction "export")
- `f`: input file (if direction "import")
- `verbose`: makes the script verbose (1..4)
- `help`: show help message

#### Resolving Team-/Queue-Names

The script is able to resolve team names given in permissions by `<TeamName2ID:Some::Full::Team::Name>` instead of numeric IDs. This is only supported in import. If a team name cannot be resolved the given pattern is replaced by `UnknownTeam_Some::Full::Team::Name`.


### Configuration

Required configuration may to be placed in a separate config file which is read upon script execution. A sample config might look like this:

```
# KIX18 params for information retrieval...
[KIXAPI]
KIXUserName        = "API-User"
KIXPassword        = "API-User-Password"
KIXURL             = http://localhost:20000
Proxy              = ""
APITimeOut         = 30

# CSV configuration ...
[CSV]
#Direction          = "export"
#CSVOutputDir       = "/tmp"
#CSVFile            = "/tmp/some.csv"
#CSVSeparator       = TAB
CSVSeparator       = ";"
CSVEncoding        = "utf-8"
CSVQuote           = "\""
```


----
## Sync from CSV-File - kix18.CSVSync.pl

Script `bin/kix18.CSVSync.pl` provides a client for importing data from CSV files to KIX18 REST-API, supporting Contact (including user), Organisation and assets (...latter some day, not yet).

Users are created/updated if a data for `Login` is given. Only then further columns such as `Password`, `Roles`, `IsAgent` and `IsCustomer` are considered at all. If there is no user context (`IsAgent` or  `IsCustomer`) set, the users account will be set to `invalid`.  `Roles` must contain **comma-separated names of roles** existing in your KIX. Only roles which match the given usage context (`IsAgent` or  `IsCustomer`) are accepted. Predefined default roles `Agent User` or `Customer` are added automatically by the script depending on the users context (hopefully no one renamed them). Non-existing or misspelled **roles will not be created.**

Dynamic Field values are split along comma and submitted as arrays by default, see config file option `DFArrayCommaSplit`.

### Required Perl Packages

For handling CSV following packages need to be installed additionally:

- CentOS
```
shell> sudo yum install libtext-csv-perl
```
- Ubuntu/Debian
```
shell> sudo apt install libtext-csv-perl libconfig-simple-perl librest-client-perl
```


### Usage
`./bin/kix18.CSVSync.pl --config ./config/kix18.CSVSync.cfg --ot Contact|Organisation`

The script can be used by referring to a configuration and object type only. Any parameter given by command line overwrites values specified in the config file. Use `kix18.CSVSync.pl --help` for a detailed parameter listing.

- `config`: path to configuration file instead of command line params
- `ot`: object to be imported (Contact|Organisation)
- `url`: URL to KIX backend API (e.g. https://t12345-api.kix.cloud)
- `u`: KIX user login
- `p`: KIX user password
- `verbose`: makes the script verbose (use `--verbose 4` for max. verbosity)
- `help`: show help message
- `i`: source directory from which CSV-files matching name patterns fpr object type are read
- `if`: source file for import (if given, option `i` is ignored)
- `o`: destination directory, where result summary is written
- `r`: if set, import files are deleted after processing
- `fpw`: if set, an updated user will get the password specified by the import data


Depending on the object type, any CSV files matching name pattern from the input directory are read. Files containing `Result` are omitted. For each import file a `SourceFileName.Result.csv` is written. Name patterns are ignored if a specific file name is given.

- object type `Asset`: name pattern `*Asset*.csv`
- object type `Contact`: name pattern `*Contact*.csv`
- object type `Organisation`: name pattern `*Org*.csv`

### Configuration

Most configuration has to be placed in a separate config file which is read upon script execution. A sample config might look like this:

```
[KIXAPI]
KIXUserName        = "API-User"
KIXPassword        = "API-User-Password"
KIXURL             = http://localhost:20000
Proxy              = ""
APITimeOut         = 30
ObjectType         = ""

# CSV configuration ...
[CSV]
RemoveSourceFile   = ""
#CSVSeparator       = TAB
CSVSeparator       = ";"
CSVInputDir        = "/workspace/tools/kix18sync/sample"
CSVOutputDir       = "/workspace/tools/kix18sync/sample"
CSVEncoding        = "utf-8"
#CSVQuote           = "none"
CSVQuote           = "\""
DFArrayCommaSplit  = "1"

# Mapping configuration ...

#Contact.Identifier                   = "Email" - NOT YET IMPLEMENTED
Contact.SearchColIndex               = "1"
Contact.ColIndex.Login               = "0"
Contact.ColIndex.Email               = "1"
Contact.ColIndex.Firstname           = "2"
Contact.ColIndex.Lastname            = "3"
Contact.ColIndex.Title               = "4"
Contact.ColIndex.Street              = "5"
Contact.ColIndex.City                = "6"
Contact.ColIndex.Zip                 = "7"
Contact.ColIndex.Country             = "8"
Contact.ColIndex.Phone               = "9"
Contact.ColIndex.Mobile              = "10"
Contact.ColIndex.Fax                 = "11"
Contact.ColIndex.Comment             = "12"
Contact.ColIndex.PrimaryOrgNo        = "13"
#Contact.ColIndex.ValidID             = "14"
Contact.ColIndex.ValidID             = "SET:1"
Contact.ColIndex.Password            = "15"
Contact.ColIndex.Roles               = "16"
#Contact.ColIndex.IsAgent             = "SET:1|0"
Contact.ColIndex.IsAgent             = "17"
#Contact.ColIndex.IsCustomer          = "SET:1|0"
Contact.ColIndex.IsCustomer          = "18"
Contact.ColIndex.DynamicField_Source = "19"


Org.SearchColIndex             = "0"
Org.ColIndex.Number            = "0"
Org.ColIndex.Name              = "1"
Org.ColIndex.Comment           = "2"
Org.ColIndex.Street            = "3"
Org.ColIndex.City              = "4"
Org.ColIndex.Zip               = "5"
Org.ColIndex.Country           = "6"
Org.ColIndex.Url               = "7"
Org.ColIndex.ValidID           = "SET:1"
Org.ColIndex.DynamicField_Type = "8"
```

----
## Sync from Database Source - kix18.DBSync.pl

Script `bin/kix18.DBSync.pl` provides a client for importing data from a remote DB to KIX18 REST-API, supporting Contact and Organisation (so far).

Dynamic Field values are split along comma and submitted as arrays by default, see config file option `DFArrayCommaSplit`.

### Required Perl Packages

Depending on the DBMS to be connected, additional packages might be required, e.g.
- CentOS
```
shell> sudo yum install perl-DBD-Pg
shell> sudo yum install perl-DBD-MySQL
shell> sudo yum install perl-DBD-ODBC
```
- Ubuntu/Debian
```
shell> sudo apt install libdbd-pg-perl
shell> sudo apt install libdbd-mysql-perl
shell> sudo apt install libdbd-odbc-perl
```


### Usage
`./bin/kix18.DBSync.pl --config ./config/kix18.DBSync.cfg --ot Contact|Organisation`

The script can be used by referring to a configuration and object type only. Any parameter given by command line overwrites values specified in the config file. Use `kix18.DBSync.pl --help` for a detailed parameter listing.

- `config`: path to configuration file instead of command line params
- `ot`: object to be imported (Contact|Organisation)
- `url`: URL to KIX backend API (e.g. https://t12345-api.kix.cloud)
- `u`: KIX user login
- `p`: KIX user password
- `du`: DBUser  (if not given by config)
- `dp`: DBPassword (if not given by config)
- `verbose`: makes the script verbose (use `--verbose 4` for max. verbosity)
- `help`: show help message


### Configuration

The major configuration has to be placed in a separate config file which is read upon script execution. A sample config might look like this:

```
# KIXAPI configuration
[KIXAPI]
KIXUserName        = "API-User"
KIXPassword        = "API-User-Password"
KIXURL             = http://localhost:20000
Proxy              = ""
APITimeOut         = 30

# DB configuration
[DB]
# DSN is the full DB connection string without username/password
#DSN                = "DBI:mysql:database=MyCRMDB;host=mariadb.server.local;"
#DSN                = "DBI:ODBC:MyODBCDBName"
DSN                = "DBI:Pg:dbname=kix17;host=kix.company.de;"
DBUser             = "SomeDBUser"
DBPassword         = "PASSWORD"
DFArrayCommaSplit  = "1"

# limit might be useful for testing (only for MySQL/MariaDB or PostgreSQL)...
DBLimit     = "100"

# following sections define the mapping of DB-tables to KIX-API resources
# Table        = "some_customer_user_table"
# Condition is optional and allows to filter relevant DB entries
# Condition    = "WHERE login != ''"
# OtherRessourceAttribute = "DB column name"
# if an attribute is not given in the DB-table it may be set to a fixed value by
# SomeRessourceAttribute = "SET:<fixedvaluehere>"

# Mapping configuration for contact items...
[Contact]
Table        = "some_customer_user"
Condition    = ""
# use condition if you want to sync. only newer entries, e.g.
# Condition    = " create_time > (current_timestamp - 86400)"
Email               = "email0"
Firstname           = "first_name"
Lastname            = "last_name"
Title               = "title"
Street              = "addr_street"
City                = "addr_city"
Zip                 = "addr_zip"
Country             = "addr_country"
Phone               = "phone1"
Mobile              = "phone2"
Fax                 = "fax1"
Comment             = "businessfnct"
PrimaryOrgNo        = "customer_id"
ValidID             = "SET:1"
#DynamicField_Source = "some_db_row"
DynamicField_Source = "SET:sample database"

# Mapping configuration for organisation items...
[Organisation]
Table             = "some_org"
Condition         = ""
Number            = "customer_id"
Name              = "name_org"
Comment           = "comments"
Street            = "addr_street"
City              = "addr_city"
Zip               = "addr_zip"
Country           = "addr_country"
Url               = "url"
ValidID           = "SET:1"
#DynamicField_Type = "SET:customer,internal supplier"
DynamicField_Type = "type"
```

PS: the DB-structure for this example in MariaDB/MySQL is contained in `sample/MyCRMDB.sql`
