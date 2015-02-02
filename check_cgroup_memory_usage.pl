#! /usr/bin/perl -w
use strict;
use Getopt::Long;

sub print_usage ();
sub cacti_mode;
sub nagios_mode;
sub get_available_cgroups;
sub get_memory_values;
sub get_correct_units;

# +-------------------------------------------------------------------------+
# | variables                                                               |
# +-------------------------------------------------------------------------+

my $PROGNAME = "cgroup_memory_usage.pl";

my $opt_h;
my $opt_l;
my $opt_M;
my $opt_C;
my $opt_w = 75;
my $opt_c = 85;
my $opt_P = "/cgroup/memory/";

# +-------------------------------------------------------------------------+
# | defining the arguments                                                  |
# +-------------------------------------------------------------------------+

Getopt::Long::Configure('no_ignore_case');
GetOptions (
	"h" => \$opt_h, "help" => \$opt_h,		# print help
	"l" => \$opt_l, "list" => \$opt_l,		# lsit available cgroups
	"M=s" => \$opt_M, "mode=s" => \$opt_M,		# nagios or cacti
	"C=s" => \$opt_C, "cgroup=s" => \$opt_C,	# cgroup to be checked, nagios mode defaults to "allcgroups"
	"w=i" => \$opt_w, "warning=i" => \$opt_w,	# warning if usage above this value (default=75, nagios only)
	"c=i" => \$opt_c, "critical=i" => \$opt_c,	# critical if usage above this valie (default=80, nagios only)
	"P=s" => \$opt_P, "path=s" => \$opt_P);		# path to the scannable data of the cgroups

# +-------------------------------------------------------------------------+
# | what we're going to do and syntax-check                                 |
# +-------------------------------------------------------------------------+

# user wants help?
if ( $opt_h ) {
	print_usage();
	exit 3;
}


# 
if ( $opt_l  ) {
	print "Following CGroups have been located: \n";
	foreach (get_available_cgroups($opt_P)) {
		print $_."\n";
	}
	exit 3;
}

# we need to know whether we're used for nagios or for cacti
if ( not defined($opt_M) ) {
	print "No mode ( nagios or cacti ) defined!\n";
	print_usage();
	exit 3;
}

# if used for cacti, there can only be one... cgroup specified
if ( ($opt_M eq 'cacti') && (not defined($opt_C)) ) {
	print "When using in mode cacti you have to specify a single cgroup\n";
	print_usage();
	exit 3;
}

# if used for nagios and no cgroup is specified, we're gonna catch 'em all
if ( ($opt_M eq 'nagios') && (not defined($opt_C)) ) {
	$opt_C = 'allcgroups';
}

# CACTI MODE INITIATED
if ( $opt_M eq 'cacti' ) {
	cacti_mode($opt_P,$opt_C);
	exit 0;
}

# NAGIOS MODE INITIATED
if ( $opt_M eq 'nagios'  ) {
	nagios_mode($opt_P,$opt_C,$opt_w,$opt_c);
}

# +-------------------------------------------------------------------------+
# | subroutines (be careful after this point)                               |
# +-------------------------------------------------------------------------+

# subroutine to print the help message
sub print_usage () {
	print "This script can either check how many percent of the available of all or a single cgroup is in use
or it can deliver cacti-compatible output to graph the memory usage of a single cgroup.
See the examples below on how to handle this piece of software\n\n";
	print "Usage for Cacti: $PROGNAME -M|--mode cacti -C|--cgroup <cgroup> [-P|--path <path to cgroups>]\n\n";
	print "Usage for Nagios $PROGNAME -M|--mode nagios
	[-w|--warning <warn percentage>] [-c|--critical <crit percentage>]
	[-C|--cgroup <cgroup>] [-P|--path <path to cgroups>]\n\n";
	print "Available Options:\n";
	print "	-h|--help
		shows this message\n\n";
	print "	-l|--list
		show all available cgroups under path\n\n";
	print "	-M|--mode
		decide whether to run as nagios check or to return cacti values (is mandatory)\n\n";
	print "	-C|--cgroup
		name a specific cgroup to be monitored
		in cacti-mode this values is mandatory
		in nagios-mode this value defaults to \"allcgroups\"\n\n";
	print "	-w|--critical
		only used in nagios-mode
		percentage of used memory at which an WARNING is raised
		( defaults to 75 )\n\n";
	print "	-c|--critical
		only used in nagios-mode
		percentage of used memory at which an CRITICAL is raised
		( defaults to 85 9\n\n";
	print "	-P|--path
		you may tell us a different path to the cgroup statistics
		( defaults to /cgroup/memory/ )\n\n";
	print "Written by Jan Scheufler in late 2011
Feel free to share, modify and improve
It's far from perfect, but it fitted my needs :D

UPDATE v1 on 2012-02-17: functionality as a nagios check added\n";
}

sub get_available_cgroups {
	# variables
	my $path = shift;
	my @cgroups;
	# list all directories under path for they are the cgroups we are looking for
	opendir(DIR,$path);
	while (my $cgroup = readdir DIR) {
	        if ( (-d $path.$cgroup) && ($cgroup ne '.') && ($cgroup ne '..') ) {
			push(@cgroups,$cgroup);
	        }
	}

	# Here we check if there are any CGroups, and if not tell the user to check his system
	my $element_count = @cgroups;
	if ( $element_count == 0  ) {
		print "CRITICAL - We were not able to locate any CGroups under the given path. You sure, you're CGroups are up and running?\n";
		exit 2;
	}
	return (@cgroups);
}


sub get_memory_values {
	# variables
	my $path = shift;
	my @memory_values;
	my $rss;
	my $hierarchical_memory_limit;
	my $tmp;
	my @formatting;
	# opening memory.stat or die
	open (MEMORYSTAT,"<","$path") or die $!;
	while (<MEMORYSTAT>) {
	$tmp = $_;
	        if ( $tmp =~ /\brss/ ) {
	                $rss = $tmp;
	        }
	        if ( $_ =~ /hierarchical_memory_limit/ )
	        {
	                $hierarchical_memory_limit = $tmp;
	        }
	}
	close (MEMORYSTAT);

	# formatting and returning rss and hierarchical_memory_limit
	# so we get rid of their name and remove all carriage returns
	@formatting = split(/ /,$rss);
	$rss = $formatting[1];
	$rss =~ s/\n//g;

	@formatting = split(/ /,$hierarchical_memory_limit);
	$hierarchical_memory_limit = $formatting[1];
	$hierarchical_memory_limit =~ s/\n//g;

	push (@memory_values,$rss);
	push (@memory_values,$hierarchical_memory_limit);

	return (@memory_values);
}


sub get_correct_units {
	# variables
	my $rss = shift;
	my $hierarchical_memory_limit = shift;

	# are we talking about GB, MB, KB or B ?
	if ( $hierarchical_memory_limit > 1073741824 ) {
		$rss = $rss / ( 1024 * 1024 * 1024 );
                $rss = sprintf("%.1f",$rss);
                $rss = $rss."GB";
                $hierarchical_memory_limit = $hierarchical_memory_limit / ( 1024 * 1024 * 1024 );
                $hierarchical_memory_limit = sprintf("%.1f",$hierarchical_memory_limit);
                $hierarchical_memory_limit = $hierarchical_memory_limit."GB";
        } elsif ( $hierarchical_memory_limit > 1048576 ) {
                $rss = $rss / ( 1024 * 1024 );
                $rss = sprintf("%.1f",$rss);
                $rss = $rss."MB";
                $hierarchical_memory_limit = $hierarchical_memory_limit / ( 1024 * 1024 );
                $hierarchical_memory_limit = sprintf("%.1f",$hierarchical_memory_limit);
                $hierarchical_memory_limit = $hierarchical_memory_limit."MB";
        } elsif ( $hierarchical_memory_limit > 1024 ) {
                $rss = $rss / ( 1024 );
                $rss = sprintf("%.1f",$rss);
                $rss = $rss."KB";
                $hierarchical_memory_limit = $hierarchical_memory_limit / ( 1024 );
                $hierarchical_memory_limit = sprintf("%.1f",$hierarchical_memory_limit);
                $hierarchical_memory_limit = $hierarchical_memory_limit."KB";
        } elsif ( $hierarchical_memory_limit <= 1024 ) {
                $rss = $rss."B";
                $hierarchical_memory_limit = $hierarchical_memory_limit."B";
	}
	return ($rss, $hierarchical_memory_limit);
}


sub cacti_mode {
	# variables
	my $path = shift;
	my $cgroup = shift;
	my @result;

	# build the path
	$path = $path.$cgroup."/memory.stat";

	# print those values
	@result = get_memory_values($path);
	print "rss:".$result[0]." ";
	print "hierarchical_memory_limit:".$result[1];

	# time to quit
	exit 0;
}


sub nagios_mode {
	# variables
	my $path = shift;
	my $cgroup = shift;
	my $warning = shift;
	my $critical = shift;

	my $path_built;

	my $cgroup_name;
	my $used;
	my $overall;
	my $used_percentage;

	my $RETURNCODE;

	my @cgroups;
	my @values;
	my @result;

	# so you really wanna check 'em all
	if ( $cgroup eq 'allcgroups' ) {
		@cgroups = get_available_cgroups($path);
		foreach (@cgroups) {
			# build the path
			$path_built = $path.$_."/memory.stat";
			# put the current cgroup_name into a variable
			$cgroup_name = $_;
			# get the current values
			@values = get_memory_values($path_built,$_);
			# write neccessary info into single variables so we can push them in an array later
			$used = $values[0];
			$overall = $values[1];
			$used_percentage = 100 * $used / $overall;
			$used_percentage=sprintf("%.0f",$used_percentage);
			# before continuing we're gonna get the correct unit for our values
			($used, $overall) = get_correct_units($used,$overall);
			# now we need a temporary array to push an array into our result array
			my @one_cgroup;
			push(@one_cgroup,($cgroup_name,$used,$overall,$used_percentage));
			push(@result,[@one_cgroup]);
		}

		# now we sort the results using the percentage, so the highest usage can be used for determining the RETURNCODE
		@result = reverse sort { $a->[3] <=> $b->[3] } @result;
		foreach (@result) {
			if ( @$_[3] >= $critical ) {
				$RETURNCODE = 2;
                                print "CRITICAL";
				last;
			}

			if ( @$_[3] >= $warning ) {
				$RETURNCODE = 1;
                                print "WARNING";
				last;
			}

                        if ( (@$_[3] < $warning) && (@$_[3] < $critical) ) {
                                $RETURNCODE = 0;
				print "OK";
				last;
                        }

		}
		# finally doing some output
		foreach (@result) {
			print " --- ".@$_[0]." ".@$_[1]." / ".@$_[2]." used ( @$_[3]% )";
		}
		exit $RETURNCODE;
	} else {
		# so it's only one cgroup you are looking for?

		# build the path
		$path = $path.$cgroup."/memory.stat";

		# get the values
	        @result = get_memory_values($path);
		$used = $result[0];
		$overall = $result[1];
		$used_percentage = 100 * $used / $overall;
		$used_percentage=sprintf("%.0f",$used_percentage);

		# before continuing we're gonna get the correct unit for our values
		($used, $overall) = get_correct_units($used,$overall);

		# determining the state
		if ( $used_percentage >= $critical ) {
			$RETURNCODE = 2;
			print "CRITICAL";
		}

		if ( $used_percentage >= $warning ) {
			$RETURNCODE = 1;
			print "WARNING";
		}

		if ( ($used_percentage < $warning) && ($used_percentage < $critical) ) {
			$RETURNCODE = 0;
			print "OK";
		}

		# output time
		print " --- ".$cgroup." ".$used." / ".$overall." used ( $used_percentage% )";
		exit $RETURNCODE;

	}
}
