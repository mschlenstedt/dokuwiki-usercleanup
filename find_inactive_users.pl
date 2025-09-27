#!/usr/bin/perl

use Getopt::Long;
use Fcntl qw(:flock);
#use Data::Dumper;
#use warnings;
use strict;

# Version of this script
my $version = "0.1.0";

# Globals
my $dbfile = "";
my $dry = 0;
my $delete = 0;
my $datafolder = "./data";
my $conffolder = "./conf";
my $help = 0;
my $checkcount = 0;
my $checkdate = 0;
my $date = 0;
my @deleteusers;

# Commandline options
GetOptions ('datafolder=s' => \$datafolder,
            'conffolder=s' => \$conffolder,
            'date=s' => \$checkdate,
            'edits=i' => \$checkcount,
            'help|?' => \$help,
            'delete=s' => \$delete,
            'file=s' => \$dbfile,
            'dry' => \$dry);

# Checks
if ($help) {
	&help();
	exit(0);
}

if ($dbfile && (! -f $dbfile || ! -d $conffolder)) {
	print "ERROR: The conf folder $conffolder does not exist or $dbfile is not a file. Please specify the correct location with --conffolder <PATH> and the file to be read with --file <FILE>\n";
	exit(1);
}
elsif (! -d $datafolder && ! $dbfile) {
	print "ERROR: The data folder $datafolder does not exist. Please specify the correct location with --datafolder <PATH>\n";
	exit(1);
}

elsif (! -d $conffolder) {
	print "ERROR: The conf folder $conffolder does not exist. Please specify the correct location with --conffolder <PATH>\n";
	exit(1);
}
elsif ($delete eq "both" && ( !$checkdate | !$checkcount)) {
	print "You have to specify a date with --date YYYY-MM-DD and the minimum edits with --edits INTEGER\n";
	exit (1);
}
elsif ($delete eq "last" && !$checkdate) {
	print "You have to specify a date with --date YYYY-MM-DD\n";
	exit (1);
}
elsif ($delete eq "edits" && !$checkcount) {
	print "You have to specify the minimum edits with --edits INTEGER\n";
	exit (1);
}
elsif ($delete && ($delete ne "edits" && $delete ne "last" && $delete ne "both")) {
	print "Delete filter can be --delete both, --delete last or --delete edits\n";
	exit (1);
}

my %userdata = findchanges();
&listall();

exit (0);


#############################################################################
# Sub routines
#############################################################################

##
## Find changes of all files and create userdata
##
sub findchanges
{
	my @changes;
	my %userdata;

	if ($checkdate) {
		$date = `date --date='$checkdate' +"%s"` # Do not use Date:Time, because on some servers not available
	}

	if ($dbfile) {
		open(F, $dbfile) or die("Could not open file $dbfile: $!");
		my @content = <F>;
		my $i = 0;
		foreach my $line (@content) {   
			$i++;
			chomp ($line);
			next if $i eq 1;
			my @fields = split(/\;/, $line);
			$userdata{$fields[1]}{'name'} = "$fields[1]";
			$userdata{$fields[1]}{'email'} = "$fields[2]";
			$userdata{$fields[1]}{'last'} = "$fields[3]";
			$userdata{$fields[1]}{'count'} = "$fields[5]";
			$userdata{$fields[1]}{'to_be_deleted'} = "$fields[6]";
		}
		close(F);
		$delete = 1;
	} else {
		open(F, $conffolder . "/users.auth.php") or die("Could not open users.auth.php file: $!");
		my @content = <F>;
		foreach my $line (@content) {   
			chomp ($line);
			if ( $line eq "" | $line =~ /^#/ ) {
				next;
			}
			my @fields = split(/\:/, $line);
			$userdata{$fields[0]}{'name'} = "$fields[2]";
			$userdata{$fields[0]}{'email'} = "$fields[3]";
			$userdata{$fields[0]}{'last'} = 0;
			$userdata{$fields[0]}{'count'} = 0;
			$userdata{$fields[0]}{'to_be_deleted'} = 0;
		}
		close(F);

		my @changesfiles = `find $datafolder/meta -name '*.changes'`;
		foreach my $file (@changesfiles) {   
			open(F, $file) or die("Could not open $file.");
			foreach my $line (<F>) {   
				chomp ( $line );
				push(@changes, $line);
			}
			close(F);

		}

		foreach ( @changes ) {
			chomp ( $_ );
			my @fields = split(/\t/, $_);
			if (! exists($userdata{$fields[4]}) ) {
				next;
			}
			if ( $userdata{$fields[4]}{'last'} < $fields[0] ) {
				$userdata{$fields[4]}{'last'} = $fields[0];
			}
			if ($checkdate && $delete ne "both") {
				$userdata{$fields['4']}{'count'}++ if $fields[0] >= $date;
			} else {
				$userdata{$fields['4']}{'count'}++;
			}
		}

		if ($delete) {
			foreach my $key (keys %userdata) {
				if ($delete eq "both") {
					if ($userdata{$key}{'last'} < $date && $userdata{$key}{'count'} < $checkcount) {
						$userdata{$key}{'to_be_deleted'} = 1;
					}
				}
				elsif ($delete eq "last") {
					if ($userdata{$key}{'last'} < $date) {
						$userdata{$key}{'to_be_deleted'} = 1;
					}
				}
				elsif ($delete eq "edits") {
					if ($userdata{$key}{'count'} < $checkcount) {
						$userdata{$key}{'to_be_deleted'} = 1;
					}
				}
			}
		}
	}

	return(%userdata);

}

##
## List all users with their last activity
##
sub listall
{

	# List as csv
	print "no;username;email;last epoch;last human;edits;to_be_deleted\n";
	my $i = 1;
	foreach my $key (sort keys %userdata) {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($userdata{$key}{'last'});
		$year += 1900;
		$mon += 1;
		my $lastdate = sprintf("%d-%02d-%02d", $year, $mon, $mday);
    		print $i . ";" . $key . ";" . $userdata{$key}{'email'} . ";" . $userdata{$key}{'last'} . ";" . $lastdate . ";" . $userdata{$key}{'count'} . ";" . $userdata{$key}{'to_be_deleted'} ."\n";
		$i++;
	}

	# Delete from database if requested
	if (($delete && !$dry) || $dbfile) {
		my $now = time();	
		qx(cp $conffolder/users.auth.php $conffolder/users.auth.php.bkp.$now);
		open(F, '+<', $conffolder . "/users.auth.php") or die("Could not open users.auth.php file: $!");
		flock(F, LOCK_EX) or die "Could not lock file users.auth.php: $!";
		my @content = <F>;
		seek(F, 0, 0);
		truncate F, 0;
		foreach my $line (@content) {   
			chomp ($line);
			my @fields = split(/\:/, $line);
			my $found = 0;
			foreach my $key (keys %userdata) {
				if ($key eq $fields[0] && $userdata{$key}{'to_be_deleted'} eq 1) {
					$found = 1;
					last;
				}
			}
			print F $line . "\n" if !$found; # Print back entry if not found
		}
		close(F);
	}

}

##
## Help
##
sub help
{

	print "Usage: $0 [OPTION]\n";
	print "Lists inactive users and optionally deletes them from database.\n";
	print "Options:\n";
	print "--conffolder <FOLDER>   : Full or relative path to Dokuwiki's conf folder.\n";
	print "                          Defaults to ./conf.\n";
	print "--datafolder <FOLDER>   : Full or relative path to Dokuwiki's data folder.\n";
	print "                          Defaults to ./data.\n";
	print "--date <YEAR-MONTH-DAY> : Counts only edits prior or euqal the given date\n";
	print "                        : or find users whose last activity is older then the\n";
	print "                          given date\n";
	print "--delete <OPTION>       : Deletes the found users from database.\n";
	print "                          Option can be:\n";
	print "                          last:  Deletes all users who haven't edited since\n";
	print "                                 the given date with --date\n";
	print "                          edits: Deletes all users who have edited less then\n";
	print "                                 the given edits with --edits\n";
	print "                          both:  Deletes all users who have edited less then\n";
	print "                                 the given edits with --edits since the\n";
	print "                                 the given date with --date\n";
	print "--dry                   : Do a dry run and do not delete anything from\n";
	print "                          database\n";
	print "--edits <INTEGER>       : Find users whose total file edits are below\n";
	print "                          <INTEGER>.\n";
	print "--file <FILE>           : Read file and delete all users with 1 in the column\n";
	print "                          'to_be_deleted'. File MUST be exactly in the format\n";
	print "                          no;username;email;last epoch;last human;edits;to_be_deleted\n";
	print "                          The first line must be the header line.\n";
	print "--help                  : Prints out this help page.\n";

}
