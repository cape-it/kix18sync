#!/usr/bin/perl -w
# --
# bin/kix18.dataimport.pl - imports CSV data into KIX18
# Copyright (C) 2006-2020 c.a.p.e. IT GmbH, http://www.cape-it.de/
#
# written/edited by:
# * Torsten(dot)Thau(at)cape(dash)it(dot)de
#
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;

use utf8;
use Encode qw/encode decode/;
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);

use DBI;
use Config::Simple;
use Getopt::Long;
use Text::CSV;
use URI::Escape;
use Pod::Usage;
use Data::Dumper;
use REST::Client;
use JSON;


# VERSION
=head1 SYNOPSIS

This script retrieves ticket- and asset information from a KIX18 by communicating with its REST-API. Information is stored locally in database tables.

Use kix18.dataimport.pl  --ot ObjectType* --help [other options]


=head1 OPTIONS

=over

=item
--ot: ObjectType  (Contact|Organisation)
=cut

=item
--config: path to configuration file instead of command line params
=cut

=item
--url: URL to KIX backend API (e.g. https://t12345-api.kix.cloud)
=cut

=item
--u: KIX user login
=cut

=item
--p: KIX user password
=cut

=item
--i: input directory
=cut


=item
--if: input file (overrides param input directory)
=cut


=item
--o: output directory
=cut

=item
--r: flag, set to remove source file after being processed
=cut

=item
--verbose: makes the script verbose
=cut

=item
--help show help message
=cut

=item
--orgsearch enables org.-lookup by search (requires hotfix in KIX18-backend!)
=cut

=back


=head1 REQUIREMENTS

The script has been developed using CentOS8 or Ubuntu as target plattform. Following packages must be installed

=over

=item
shell> sudo yum install perl-Config-Simple perl-REST-Client perl-JSO perl-LWP-Protocol-https perl-DBI perl-URI perl-Pod-Usage perl-Getopt-Long  libtext-csv-perl
=cut

=item
shell> sudo apt install libconfig-simple-perl librest-client-perl libjson-perl liblwp-protocol-https-perl libdbi-perl liburi-perl perl-doc libgetopt-long-descriptive-perl
=cut

=back

=cut

my $Help           = 0;
my %Config         = ();
$Config{Verbose}           = 0;
$Config{RemoveSourceFile}  = 0;
$Config{ConfigFilePath}    = "";
$Config{KIXURL}            = "";
$Config{KIXUserName}       = "";
$Config{KIXPassword}       = "";

# read some params from command line...
GetOptions (
  "config=s"   => \$Config{ConfigFilePath},
  "url=s"      => \$Config{KIXURL},
  "u=s"        => \$Config{KIXUserName},
  "p=s"        => \$Config{KIXPassword},
  "ot=s"       => \$Config{ObjectType},
  "i=s"        => \$Config{CSVInputDir},
  "if=s"       => \$Config{CSVInputFile},
  "o=s"        => \$Config{CSVOutputDir},
  "r"          => \$Config{RemoveSourceFile},
  "verbose=i"  => \$Config{Verbose},
  # temporary workaround...
  "orgsearch"  => \$Config{OrgSearch},
  "help"       => \$Help,
);

if( $Help ) {
  pod2usage( -verbose => 3);
  exit(-1)
}


if( $Config{CSVInputFile} ) {
  print STDOUT "\nInput file given - ignoring input directory." if( $Config{Verbose});
  my $basename = basename( $Config{CSVInputFile} );
  my $dirname  = dirname( $Config{CSVInputFile} );
  $Config{CSVInputDir} = $dirname;
  $Config{CSVInputFile} = $basename;
}



# read config file...
my %FileConfig = ();
if( $Config{ConfigFilePath} ) {
    print STDOUT "\nReading config file $Config{ConfigFilePath} ..." if( $Config{Verbose});
    Config::Simple->import_from( $Config{ConfigFilePath}, \%FileConfig);

    for my $CurrKey ( keys( %FileConfig )) {
      my $LocalKey = $CurrKey;
      $LocalKey =~ s/(CSV\.|KIXAPI.|CSVMap.)//g;
      $Config{$LocalKey} = $FileConfig{$CurrKey} if(!$Config{$LocalKey});
    }

}



# check requried params...
for my $CurrKey (qw{KIXURL KIXUserName KIXPassword ObjectType CSVInputDir}) {
  next if($Config{$CurrKey});
  print STDERR "\nParam $CurrKey required but not defined - aborting.\n\n";
  pod2usage( -verbose => 1);
  exit(-1)
}


if( $Config{Verbose} > 1) {
  print STDOUT "\nFollowing configuration is used:\n";
  for my $CurrKey( sort( keys( %Config ) ) ) {
    print STDOUT sprintf( "\t%30s: ".($Config{$CurrKey} || '-')."\n" , $CurrKey, );
  }
}

# read source CSV file...
my $CSVDataRef = _ReadSources( { %Config} );
exit(-1) if !$CSVDataRef;


# log into KIX-Backend API
my $KIXClient = _KIXAPIConnect( %Config  );
exit(-1) if !$KIXClient;

my $Result = 0;

# import CSV-data...
my $ResultData = $CSVDataRef;
if ( $Config{ObjectType} eq 'Asset') {

  # lookup asset classes...
  my %AssetClassList = _KIXAPIGeneralCatalogList(
    { %Config, Client => $KIXClient, Class => 'ITSM::ConfigItem::Class'}
  );

  # lookup deployment states...
  my %DeplStateList = _KIXAPIGeneralCatalogList(
    { %Config, Client => $KIXClient, Class => 'ITSM::ConfigItem::DeploymentState'}
  );

  # lookup incident states...
  my %InciStateList = _KIXAPIGeneralCatalogList(
    { %Config, Client => $KIXClient, Class => 'ITSM::Core::IncidentState'}
  );

  print STDERR "\nAsset import not supported yet - aborting.\n\n";
  pod2usage( -verbose => 1);
  exit(-1)

}
elsif ( $Config{ObjectType} eq 'Contact') {

  # process import lines
  for my $CurrFile ( keys( %{$CSVDataRef}) ) {

    my $LineCount = 0;

    for my $CurrLine ( @{$CSVDataRef->{$CurrFile}} ) {

      # skip first line (ignore header)...
      if ( $LineCount < 1) {
        $LineCount++;
        next;
      }

      if( !$CurrLine->[$Config{'Contact.SearchColIndex'}] ) {
        push( @{$CurrLine}, 'ERROR');
        push( @{$CurrLine}, 'Identifier missing.');
        print STDOUT "$LineCount: identifier missing.\n";
        next;
      }

      my $OrgID = undef;
      if( $CurrLine->[$Config{'Contact.ColIndex.PrimaryOrgNo'}] ) {

        my %OrgID = _KIXAPISearchOrg({
          %Config,
          Client      => $KIXClient,
          SearchValue => $CurrLine->[$Config{'Contact.ColIndex.PrimaryOrgNo'}] || '-',
        });

        if ( $OrgID{ID} ) {
          $OrgID = $OrgID{ID};
        }
        else {
          print STDOUT "$LineCount: no organization found for <"
            . $CurrLine->[$Config{'Contact.ColIndex.PrimaryOrgNo'}]
            . ">.\n"
        }
      }

      my %Contact = (
          City            => $CurrLine->[$Config{'Contact.ColIndex.City'}],
          Comment         => $CurrLine->[$Config{'Contact.ColIndex.Comment'}],
          Country         => $CurrLine->[$Config{'Contact.ColIndex.Country'}],
          Email           => $CurrLine->[$Config{'Contact.ColIndex.Email'}],
          Fax             => $CurrLine->[$Config{'Contact.ColIndex.Fax'}],
          Firstname       => $CurrLine->[$Config{'Contact.ColIndex.Firstname'}],
          Lastname        => $CurrLine->[$Config{'Contact.ColIndex.Lastname'}],
          Login           => $CurrLine->[$Config{'Contact.ColIndex.Login'}],
          Mobile          => $CurrLine->[$Config{'Contact.ColIndex.Mobile'}],
          Phone           => $CurrLine->[$Config{'Contact.ColIndex.Phone'}],
          Street          => $CurrLine->[$Config{'Contact.ColIndex.Street'}],
          Title           => $CurrLine->[$Config{'Contact.ColIndex.Title'}],
          ValidID         => $CurrLine->[$Config{'Contact.ColIndex.ValidID'}],
          Zip             => $CurrLine->[$Config{'Contact.ColIndex.Zip'}],
      );


      if( $OrgID ) {
        my @OrgIDs = ();
        push( @OrgIDs, $OrgID);
        $Contact{OrganisationIDs} = \@OrgIDs;
        $Contact{PrimaryOrganisationID} = $OrgID;        
      }

      # search contact...
      my %SearchResult = _KIXAPISearchContact({
        %Config,
        Client      => $KIXClient,
        SearchValue => $CurrLine->[$Config{'Contact.SearchColIndex'}] || '-'
      });

      # handle errors...
      if ( $SearchResult{Msg} ) {
        push( @{$CurrLine}, 'ERROR');
        push( @{$CurrLine}, $SearchResult{Msg});

      }

      # update existing $Contact...
      elsif ( $SearchResult{ID} ) {
        $Contact{ID} = $SearchResult{ID};
        my $ContactID = _KIXAPIUpdateContact(
          { %Config, Client => $KIXClient, Contact => \%Contact }
        );

        if( !$ContactID) {
          push( @{$CurrLine}, 'ERROR');
          push( @{$CurrLine}, 'Update failed.');
        }
        elsif ( $ContactID == 1 ) {
          push( @{$CurrLine}, 'no update required');
          push( @{$CurrLine}, $SearchResult{Msg});
        }
        else {
          push( @{$CurrLine}, 'update');
          push( @{$CurrLine}, $SearchResult{Msg});
        }

        print STDOUT "$LineCount: Updated contact <$SearchResult{ID}> for <Email "
          . $Contact{Email}
          . ">.\n"
        if( $Config{Verbose} > 2);
      }
      # create new contact...
      else {

        my $NewContactID = _KIXAPICreateContact(
          { %Config, Client => $KIXClient, Contact => \%Contact }
        ) || '';

        if ( $NewContactID ) {
          push( @{$CurrLine}, 'created');
          push( @{$CurrLine}, $SearchResult{Msg});
        }
        else {
          push( @{$CurrLine}, 'ERROR');
          push( @{$CurrLine}, 'Create failed.');
        }

        print STDOUT "$LineCount: Created contact <$NewContactID> for <Email "
          . $Contact{Email}. ">.\n"
        if( $Config{Verbose} > 2);
      }

      $LineCount++;
    }
  }

}
elsif ( $Config{ObjectType} eq 'Organisation') {

  # process import lines
  for my $CurrFile ( keys( %{$CSVDataRef}) ) {

    my $LineCount = 0;

    for my $CurrLine ( @{$CSVDataRef->{$CurrFile}} ) {

      # skip first line (ignore header)...
      if ( $LineCount < 1) {
        $LineCount++;
        next;
      }

      if( !$CurrLine->[$Config{'Org.SearchColIndex'}] ) {
        push( @{$CurrLine}, 'ERROR');
        push( @{$CurrLine}, 'Identifier missing.');
        print STDOUT "$LineCount: identifier missing.\n";
        next;
      }

      my %Organization = (
          City            => $CurrLine->[$Config{'Org.ColIndex.City'}],
          Number   => $CurrLine->[$Config{'Org.ColIndex.Number'}],
          Name     => $CurrLine->[$Config{'Org.ColIndex.Name'}],
          Comment  => $CurrLine->[$Config{'Org.ColIndex.Comment'}],
          Street   => $CurrLine->[$Config{'Org.ColIndex.Street'}],
          City     => $CurrLine->[$Config{'Org.ColIndex.City'}],
          Zip      => $CurrLine->[$Config{'Org.ColIndex.Zip'}],
          Country  => $CurrLine->[$Config{'Org.ColIndex.Country'}],
          Url      => $CurrLine->[$Config{'Org.ColIndex.Url'}],
          ValidID  => $CurrLine->[$Config{'Org.ColIndex.ValidID'}],
      );

      # search organisation...
      my %SearchResult = _KIXAPISearchOrg({
        %Config,
        Client      => $KIXClient,
        SearchValue => $CurrLine->[$Config{'Org.SearchColIndex'}] || '-'
      });

      # handle errors...
      if ( $SearchResult{Msg} ) {
        push( @{$CurrLine}, 'ERROR');
        push( @{$CurrLine}, $SearchResult{Msg});
      }

      # update existing organisation...
      elsif ( $SearchResult{ID} ) {
        $Organization{ID} = $SearchResult{ID};
        my $OrgID = _KIXAPIUpdateOrg(
          { %Config, Client => $KIXClient, Organization => \%Organization }
        );

        if( !$OrgID) {
          push( @{$CurrLine}, 'ERROR');
          push( @{$CurrLine}, 'Update failed.');
        }
        elsif ( $OrgID == 1 ) {
          push( @{$CurrLine}, 'no update required');
          push( @{$CurrLine}, $SearchResult{Msg});
        }
        else {
          push( @{$CurrLine}, 'update');
          push( @{$CurrLine}, $SearchResult{Msg});
        }

        print STDOUT "$LineCount: Updated organisation <$OrgID> for <"
          . $Organization{Number}
          . ">.\n"
          if( $Config{Verbose} > 2);
      }

      # create new organisation...
      else {

        my $NewOrgID = _KIXAPICreateOrg(
          { %Config, Client => $KIXClient, Organization => \%Organization }
        );

        if ( $NewOrgID ) {
          push( @{$CurrLine}, 'created');
          push( @{$CurrLine}, $SearchResult{Msg});
        }
        else {
          push( @{$CurrLine}, 'ERROR');
          push( @{$CurrLine}, 'Create failed.');
        }

        print STDOUT "$LineCount: Created organisation <$NewOrgID> for <"
          .$Organization{Number}. ">.\n"
          if( $Config{Verbose} > 2);
      }

      $LineCount++;
    }
  }

}
else {
  print STDERR "\nUnknown object type '$Config{ObjectType}' - aborting.\n\n";
  pod2usage( -verbose => 1);
  exit(-1)
}


# write result file and cleanup...
_WriteResult( { %Config, Data => $ResultData} );


print STDOUT "\nDone.\n";
exit(0);




# ------------------------------------------------------------------------------
# KIX API Helper FUNCTIONS
sub _KIXAPIConnect {
  my (%Params) = @_;
  my $Result = 0;

  # connect to webservice
  my $AccessToken = "";
  my $Headers = {Accept => 'application/json', };
  my $RequestBody = {
  	"UserLogin" => $Config{KIXUserName},
  	"Password" =>  $Config{KIXPassword},
  	"UserType" => "Agent"
  };

  my $Client = REST::Client->new(
    host    => $Config{KIXURL},
    timeout => $Config{APITimeOut} || 15,
  );
  $Client->getUseragent()->proxy(['http','https'], $Config{Proxy});
  $Client->POST(
      "/api/v1/auth",
      to_json( $RequestBody ),
      $Headers
  );

  if( $Client->responseCode() ne "201") {
    print STDERR "\nCannot login to $Config{KIXURL}/api/v1/auth (user: "
      .$Config{KIXUserName}.". Response ".$Client->responseCode().")!\n";
    exit(-1);
  }
  else {
    my $Response = from_json( $Client->responseContent() );
    $AccessToken = $Response->{Token};
    print STDOUT "Connected to $Config{KIXURL}/api/v1/ (user: "
      ."$Config{KIXUserName}).\n" if( $Config{Verbose} > 1);

  }

  $Client->addHeader('Accept', 'application/json');
  $Client->addHeader('Content-Type', 'application/json');
  $Client->addHeader('Authorization', "Token ".$AccessToken);

  return $Client;
}



#-------------------------------------------------------------------------------
# CONTACT HANDLING FUNCTIONS KIX-API
sub _KIXAPISearchContact {

    my %Params = %{$_[0]};
    my %Result = (
       ID => 0,
       Msg => ''
    );
    my $Client = $Params{Client};

    my @ResultItemData = qw{};
    my @Conditions = qw{};

    my $IdentAttr  = $Params{Identifier} || "";
    my $IdentStrg  = $Params{SearchValue} || "";

    print STDOUT "Search contact by Email EQ '$IdentStrg'"
      .".\n" if( $Config{Verbose} > 3);

    push( @Conditions,
      {
        "Field"    => "Email",
        "Operator" => "EQ",
        "Type"     => "STRING",
        "Value"    => $IdentStrg
      }
    );

    my $Query = {};
    $Query->{Contact}->{AND} =\@Conditions;
    my @QueryParams = (
      "search=".uri_escape( to_json( $Query)),
    );
    my $QueryParamStr = join( ";", @QueryParams);

    $Params{Client}->GET( "/api/v1/contacts?$QueryParamStr");

    if( $Client->responseCode() ne "200") {
      $Result{Msg} = "Search for contacts failed (Response ".$Client->responseCode().")!";
    }
    else {
      my $Response = from_json( $Client->responseContent() );
      if( scalar(@{$Response->{Contact}}) > 1 ) {
        $Result{Msg} = "More than on item found for identifier.";
      }
      elsif( scalar(@{$Response->{Contact}}) == 1 ) {
        $Result{ID} = $Response->{Contact}->[0]->{ID};
      }
    }

   return %Result;
}



sub _KIXAPIUpdateContact {

  my %Params = %{$_[0]};
  my $Result = 0;

  $Params{Contact}->{ValidID} = $Params{Contact}->{ValidID} || 1;

  my $RequestBody = {
    "Contact" => {
        %{$Params{Contact}}
    }
  };

  $Params{Client}->PATCH( "/api/v1/contacts/".$Params{Contact}->{ID}, to_json( $RequestBody ));

  #  update ok...
  if( $Params{Client}->responseCode() eq "200") {
    my $Response = from_json( $Params{Client}->responseContent() );
    $Result = $Response->{ContactID};
  }
  else {
    print STDERR "Updating contact failed (Response ".$Params{Client}->responseCode().")!\n";
  }

  return $Result;

}



sub _KIXAPICreateContact {

  my %Params = %{$_[0]};
  my $Result = 0;

  $Params{Contact}->{ValidID} = $Params{Contact}->{ValidID} || 1;

  my $RequestBody = {
    "Contact" => {
        %{$Params{Contact}}
    }
  };

  $Params{Client}->POST(
      "/api/v1/contacts",
      encode("utf-8",to_json( $RequestBody ))
  );

  if( $Params{Client}->responseCode() ne "201") {
    print STDERR "\nCreating contact failed (Response ".$Params{Client}->responseCode().")!\n";
    $Result = 0;
  }
  else {
    my $Response = from_json( $Params{Client}->responseContent() );
    $Result = $Response->{ContactID};
  }

  return $Result;

}



#-------------------------------------------------------------------------------
# ORGANISATION HANDLING FUNCTIONS KIX-API
sub _KIXAPISearchOrg {

    my %Params = %{$_[0]};
    my %Result = (
       ID => 0,
       Msg => ''
    );
    my $Client = $Params{Client};

    my @ResultItemData = qw{};
    my @Conditions = qw{};

    my $IdentAttr  = $Params{Identifier} || "";
    my $IdentStrg  = $Params{SearchValue} || "";

    print STDOUT "Search organisation by Number EQ '$IdentStrg'"
      .".\n" if( $Config{Verbose} > 2);

    push( @Conditions,
      {
        "Field"    => "Number",
        "Operator" => "EQ",
        "Type"     => "STRING",
        "Value"    => $IdentStrg
      }
    );

    my $Query = {};
    $Query->{Organisation}->{AND} =\@Conditions;
    my @QueryParams = qw{};

    if( $Config{OrgSearch} ) {
      @QueryParams =  ("search=".uri_escape( to_json( $Query)),);

    }
    else {
        @QueryParams =  ("filter=".uri_escape( to_json( $Query)),);
    }

    my $QueryParamStr = join( ";", @QueryParams);

    $Params{Client}->GET( "/api/v1/organisations?$QueryParamStr");

    # this is a q&d workaround for occasionally 500 response which cannot be
    # explained yet...
    if( $Client->responseCode() eq "500") {
      $Params{Client}->GET( "/api/v1/organisations?$QueryParamStr");
    }

    if( $Client->responseCode() ne "200") {
      $Result{Msg} = "Search for organisations failed (Response ".$Client->responseCode().")!";
      exit(0);
    }
    else {
      my $Response = from_json( $Client->responseContent() );

      if( scalar(@{$Response->{Organisation}}) > 1 ) {
        $Result{Msg} = "More than on item found for identifier.";
      }
      elsif( scalar(@{$Response->{Organisation}}) == 1 ) {
        $Result{ID} = $Response->{Organisation}->[0]->{ID};
      }
    }
   return %Result;
}




sub _KIXAPIUpdateOrg {

  my %Params = %{$_[0]};
  my $Result = 0;

  $Params{Organization}->{ValidID} = $Params{Organization}->{ValidID} || 1;

  my $RequestBody = {
    "Organisation" => {
        %{$Params{Organization}}
    }
  };

  $Params{Client}->PATCH(
      "/api/v1/organisations/".$Params{Organization}->{ID},
      encode("utf-8",to_json( $RequestBody ))
  );

  #  update ok...
  if( $Params{Client}->responseCode() eq "200") {
    my $Response = from_json( $Params{Client}->responseContent() );
    $Result = $Response->{OrganisationID};
  }
  else {
    print STDERR "Updating contact failed (Response ".$Params{Client}->responseCode().")!\n";
  }

  return $Result;

}



sub _KIXAPICreateOrg {

  my %Params = %{$_[0]};
  my $Result = 0;

  $Params{Organization}->{ValidID} = $Params{Organization}->{ValidID} || 1;


  my $RequestBody = {
    "Organisation" => {
        %{$Params{Organization}}
    }
  };


  $Params{Client}->POST(
      "/api/v1/organisations",
      encode("utf-8", to_json( $RequestBody ))
  );

  if( $Params{Client}->responseCode() ne "201") {
    print STDERR "\nCreating organisation failed (Response ".$Params{Client}->responseCode().")!\n";
    $Result = 0;
  }
  else {
    my $Response = from_json( $Params{Client}->responseContent() );
    $Result = $Response->{OrganisationID};
  }

  return $Result;

}






#-------------------------------------------------------------------------------
# ASSET HANDLING FUNCTIONS KIX-API
sub _KIXAPISearchAsset {

    my %Params = %{$_[0]};
    my %Result = (
       ID => 0,
       Msg => ''
    );
    my $Client = $Params{Client};

    my @ResultItemData = qw{};
    my @Conditions = qw{};

    my $IdentAttr  = $Params{Identifier} || "";
    my $IdentStrg  = $Params{SearchValue} || "";

    print STDOUT "Search asset by Number EQ '$IdentStrg' or "
      ." <$IdentAttr> EQ '$IdentStrg'"
      .".\n" if( $Config{Verbose} > 3);

    push( @Conditions,
      {
        "Field"    => "Number",
        "Operator" => "EQ",
        "Type"     => "STRING",
        "Value"    => $IdentStrg
      }
    );
    push( @Conditions,
      {
        "Field"    => $IdentAttr,
        "Operator" => "EQ",
        "Type"     => "STRING",
        "Value"    => $IdentStrg
      }
    );

    my $Query = {};
    $Query->{ConfigItem}->{OR} =\@Conditions;
    my @QueryParams = (
      "search=".uri_escape( to_json( $Query)),
    );
    my $QueryParamStr = join( ";", @QueryParams);

    $Params{Client}->GET( "/api/v1/cmdb/configitems?$QueryParamStr");

    if( $Client->responseCode() ne "200") {
      $Result{Msg} = "Search for asset failed (Response ".$Client->responseCode().")!";
    }
    else {

      my $Response = from_json( $Client->responseContent() );
      if( scalar(@{$Response->{ConfigItem}}) > 1 ) {
        $Result{Msg} = "More than on item found for identifier.";
      }
      elsif( scalar(@{$Response->{ConfigItem}}) == 1 ) {
        $Result{ID} = $Response->{ConfigItem}->[0]->{ConfigItemID};
      }
    }

   return %Result;
}



sub _KIXAPIUpdateAsset {

  my %Params = %{$_[0]};
  my $Result = 0;

  my $RequestBody = {
    "ConfigItemVersion" => {
      "DeplStateID" => $Params{Asset}->{DeplStateID},
      "InciStateID" => $Params{Asset}->{InciStateID},
      "Name"        => $Params{Asset}->{Name},
      "Data" => {

        # this is the part which is CI-class specific, e.g.
        "SectionGeneral" => {
          "ExternalInvNo" => $Params{Asset}->{ExtInvNumber},
          "Vendor"        => $Params{Asset}->{VendorName},
          "Model"         => $Params{Asset}->{ModelName},
        }
      }
    }
  };

  $Params{Client}->POST(
      "/api/v1/cmdb/configitems/".$Params{Asset}->{ID}."/versions",
      encode("utf-8", to_json( $RequestBody ))
  );

  # no update required...
  if( $Params{Client}->responseCode() eq "200") {
    $Result = 1
  }
  # new version added...
  elsif( $Params{Client}->responseCode() eq "201") {
    my $Response = from_json( $Params{Client}->responseContent() );
    $Result = $Response->{VersionID};
  }
  else {
    print STDERR "Updating asset failed (Response ".$Params{Client}->responseCode().")!\n";
  }

  return $Result;

}



sub _KIXAPICreateAsset {

  my %Params = %{$_[0]};
  my $Result = 0;

  my $RequestBody = {
  	"ConfigItem" => {
      "ClassID" => $Params{Asset}->{AssetClassID},
      "Version" => {
        "DeplStateID" => $Params{Asset}->{DeplStateID},
        "InciStateID" => $Params{Asset}->{InciStateID},
        "Name"        => $Params{Asset}->{Name},
        "Data" => {
          # this is the part which is CI-class specific, e.g.
          "SectionGeneral" => {
            "ExternalInvNo" => $Params{Asset}->{ExtInvNumber},
            "Vendor"        => $Params{Asset}->{VendorName},
            "Model"         => $Params{Asset}->{ModelName},
          }
        }
      }
    }
  };

  $Params{Client}->POST(
      "/api/v1/cmdb/configitems",
      encode("utf-8", to_json( $RequestBody ))
  );

  if( $Params{Client}->responseCode() ne "201") {
    print STDERR "\nCreating asset failed (Response ".$Params{Client}->responseCode().")!\n";
    $Result = 0;
  }
  else {
    my $Response = from_json( $Params{Client}->responseContent() );
    $Result = $Response->{ConfigItemID};
  }

  return $Result;

}



sub _KIXAPIGeneralCatalogList {

  my %Params = %{$_[0]};
  my %Result = ();
  my $Client = $Params{Client};
  my $Class  = $Params{Class} || "-";
  my $Valid  = $Params{Valid} || "valid";

  my @Conditions = qw{};
  push( @Conditions,
    {
      "Field"    => "Class",
      "Operator" => "EQ",
      "Type"     => "STRING",
      "Value"    => $Class
    }
  );

  my $Query = {};
  $Query->{GeneralCatalogItem}->{AND} =\@Conditions;
  my @QueryParams = (
    "filter=".uri_escape( to_json( $Query)),
  );
  my $QueryParamStr = join( ";", @QueryParams);

  $Params{Client}->GET( "/api/v1/system/generalcatalog?$QueryParamStr");

  if( $Client->responseCode() ne "200") {
    print STDERR "\nSearch for GC class failed (Response ".$Client->responseCode().")!\n";
    exit(-1);
  }
  else {
    my $Response = from_json( $Client->responseContent() );
    for my $CurrItem ( @{$Response->{GeneralCatalogItem}}) {
      $Result{ $CurrItem->{Name} } = $CurrItem->{ItemID};
    }
  }

  return %Result;
}


#-------------------------------------------------------------------------------
# FILE HANDLING FUNCTIONS

sub _ReadSources {
  my %Params = %{$_[0]};
  my %Result = ();


  # prepare CSV parsing...
  if( $Params{CSVSeparator} =~ /^tab.*/i) {
    $Params{CSVSeparator} = "\t";
  }
  if( $Params{CSVQuote} =~ /^none.*/i) {
    $Params{CSVQuote} = undef;
  }
  my $InCSV = Text::CSV->new (
    {
      binary => 1,
      auto_diag => 1,
      sep_char   => $Params{CSVSeparator},
      quote_char => $Params{CSVQuote},
      # new-line-handling may be modified TO DO
      #eol => "\r\n",
    }
  );


  #find relevant import files....
  my @ImportFiles = qw{};

  if( $Params{CSVInputFile} ) {
      push(@ImportFiles, $Params{CSVInputFile});
  }
  # read file pattern depending on import object type...
  else {
    opendir( DIR, $Params{CSVInputDir} ) or die $!;
    while ( my $File = readdir(DIR) || '' ) {

    	next if ( $File =~ m/^\./ );

      if( $Params{ObjectType} eq 'Asset' ) {
        next if ( $File !~ m/(.*)Asset(.+)\.csv$/ );
      }
      elsif( $Params{ObjectType} eq 'Contact' ) {
        next if ( $File !~ m/(.*)Contact(.+)\.csv$/ );
      }
      elsif( $Params{ObjectType} eq 'Organisation' ) {
        next if ( $File !~ m/(.*)Org(.+)\.csv$/ );
      }
      else {
        next;
      }
      next if ( $File =~ m/\.Result\./ );
      print STDOUT "\tFound import file $File".".\n" if( $Config{Verbose} > 1);
      push( @ImportFiles, $File);

    }
    closedir(DIR);
  }



  # import CSV-files to arrays...
  for my $CurrFile ( sort(@ImportFiles) ) {
    my $CurrFileName = $Config{CSVInputDir}."/".$CurrFile;
    my @ResultItemData = qw{};

    open my $FH, "<:encoding(".$Params{CSVEncoding}.")", $CurrFileName  or die "Could not read $CurrFileName: $!";

    $Result{"$CurrFile"} = $InCSV->getline_all ($FH);
    print STDOUT "Reading import file $CurrFileName".".\n" if( $Config{Verbose} > 2);

    close $FH;

  }

  print STDOUT "Read ".(scalar(keys(%Result)) )." import files.\n" if( $Config{Verbose} );


  return \%Result;
}


sub _WriteResult {
  my %Params = %{$_[0]};
  my $Result = 0;


  if( $Params{CSVSeparator} =~ /^tab.*/i) {
    $Params{CSVSeparator} = "\t";
  }
  if( $Params{CSVQuote} =~ /^none.*/i) {
    $Params{CSVQuote} = undef;
  }
  my $OutCSV = Text::CSV->new (
    {
      binary => 1,
      auto_diag => 1,
      sep_char   => $Params{CSVSeparator},
      quote_char => $Params{CSVQuote},
      eol => "\r\n",
    }
  );

  for my $CurrFile ( keys( %{$Params{Data}}) ) {

    my $ResultFileName = $CurrFile;
    $ResultFileName =~ s/\.csv/\.Result\.csv/g;
    my $OutputFileName = $Params{CSVOutputDir}."/".$ResultFileName;

    open ( my $FH, ">:encoding(".$Params{CSVEncoding}.")",
      $OutputFileName) or die "Could not write $OutputFileName: $!";

    for my $CurrLine ( @{$Params{Data}->{$CurrFile}} ) {
      $OutCSV->print ($FH, $CurrLine );
    }

    print STDOUT "\nWriting import result to <$OutputFileName>.";
    close $FH or die "Error while writing $Params{CSVOutput}: $!";

    if( $Params{RemoveSourceFile} ) {
      unlink( $Params{CSVInputDir}."/".$CurrFile );
    }

  }




}


1;