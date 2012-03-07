#!/usr/bin/perl  

$debug=0 ;


$MIN_NUM_THREADS=1;
$MAX_NUM_THREADS=2;
$THREAD_STEP=1;
$NUM_THREADS=$MAX_NUM_THREADS; # deprecated

$NO_OUTPUT_FILE = 0; 

$DATA_DIR = 'DATA/';
$DATASET_EXT = '.dat';
$TIMEOUT=150; #In number of cycles
$CYCLE_LEN=10; #in sec.
$MAX_MEM_USAGE=60000000;




#hash that remembers order. 
use Tie::IxHash;
tie %bin, 'Tie::IxHash';


sub md5_file{
    my $file = $_[0];
    use Digest::MD5;
    open(FILE, $file) or die "Can't open '$file': $!";
    binmode(FILE);

    return Digest::MD5->new->addfile(*FILE)->hexdigest;
}
 
sub date_string{
    use POSIX qw/strftime/;
    return strftime('%F %T',localtime); 
}
$START_TIME = date_string;




sub check_memory_usage{
    my $name = $_[0];
    open INPUT, 'ps -eo comm,rss | awk \'/'.$name.'/ && !/awk/ {print $2}\'|'; 
    my $mem = <INPUT>;
    close INPUT;
    print MEM "$current_time $mem"; 
    if($mem >= $MAX_MEM_USAGE){
	print STDERR "Process $name uses more than $MAX_MEM_USAGE kiB : $mem\n"; 
	return 1; 
    }
    else {
	return 0; 
    }
}


$child_pid=-1; 

$current_time = 0; 
$SIG {ALRM} = sub {
    #
    $current_time++; 
    if(check_memory_usage($process_name) or $current_time >= $TIMEOUT){
	print STDERR "killing $process_name\n"; 
	do{
	    system("killall -9 $process_name\n");  
	    sleep(1); 
	}
	while($_); 
    }
    else {
	alarm $CYCLE_LEN;
    }
};

sub run_child{
    my $command = $_[0];
    $process_name = $_[1]; 
    my $nb_threads = $_[2];
#    $child_pid = 0;  
#    eval{
       
    print STDERR " pn :$command\n";
    if( $command =~ /.*?\/?([\w\-]+)\s/gx){
	$process_name = $1;
	print STDERR " pn :$process_name\n"
    }
    else {
	print STDERR "Error : cannot parse process name \n"; 
    }
   

    $child_pid = fork;
    if (not $child_pid) {
	not $NO_OUTPUT_FILE and print "exec : $command (timout : ".$TIMEOUT.")\n"; 
	
	exec "/usr/bin/time -o time.dat -f \"%e\" $command 2>&1 > out_tmp " or die "command failed\n"; 
    }
    alarm $CYCLE_LEN;
    waitpid($child_pid, 0); 
    alarm 0;
    if($? != 0){
	return  -1; 
    }
    
    my $time;
    open TIME, "time.dat" or die "cannot open time file\n";
    $time = <TIME>; 
    chomp $time; 
    close TIME; 
not $NO_OUTPUT_FILE and print "Run time : ".($time)."\n";
    
    return $time; 

#     $child_pid = fork();
#     if($child_pid == 0){
# 	print STDOUT "running $command in process\n"; 
# 	exec "$command 2>&1 > out_tmp" or die; 
# 	die; 
#     }
#     $SIG{ALRM} = sub { print "KILLING $child_pid\n"; kill 15, $child_pid or kill 9, $child_pid or print  "WARNING could not kill child process $child_pid.\n"; print STDOUT "killed $child_pid after $TIMEOUT s\n";   };
#     alarm($TIMEOUT);
#     print "CREATED CHILD $child_pid\n";

#     waitpid($child_pid,0) or die "Couldnot wait child_n";
#     alarm(0);
#     print STDOUT "$child_pid done !\n"; 

#    }

    
}

#if($plot_data){
# plot_data; 
# }

#for dci 

$OUTPUTDIR="times/dat/";
system("mkdir -p $OUTPUTDIR"); 
system("mkdir -p $OUTPUTDIR/dumps"); 
system("mkdir -p $OUTPUTDIR/mem"); 

sub run{
    my ($name, $bin, $command_line_pattern, $extract_time_func, $par) = @_; 

    my $md5 = md5_file($bin); 
    use Sys::Hostname;
    my $hostname = hostname; 


    for($ds = 0; $ds <= $#DATASET_NAME; $ds++){
	if($NO_OUTPUT_FILE){
	    open(OUTPUT, ">&STDERR"); 
	    print(OUTPUT "# RUNNING $name on ".$DATASET_NAME[$ds].'@'.$DATASET_SUP[$ds]."\n");
	}
	else{
	open OUTPUT, '>', "$OUTPUTDIR/".$DATASET_NAME[$ds].'@'.$DATASET_SUP[$ds].'_'.$name.'.dat';
	open MEM, '>', "$OUTPUTDIR/mem/".$DATASET_NAME[$ds].'@'.$DATASET_SUP[$ds].'_'.$name.'.dat';
	##BUGGY
	$current_time = 0; 
	print OUTPUT "# Overall experiment start at $START_TIME on $hostname\n";
	print OUTPUT "# Date : ".date_string()."\n";
	print OUTPUT "# nb_threads in [$MIN_NUM_THREADS, $MAX_NUM_THREADS].\n";
	print OUTPUT "# file $bin (MD5 : $md5).\n";
	print OUTPUT "#\n# <nbthreads> <wallclock time> <usertime>\n";

	print MEM "# Overall experiment start at $START_TIME on $hostname\n";
	print MEM "# Date : ".date_string()."\n";
	print MEM "# nb_threads in [$MIN_NUM_THREADS, $MAX_NUM_THREADS].\n";
	print MEM "# file $bin (MD5 : $md5).\n";
	print MEM "#\n# <cylce id($CYCLE_LEN)> <mem usage (kiB)>\n";
	

	}

	my $wallclock_time = -1; 
	my $time = -1; 
	for($tt=$MIN_NUM_THREADS; $tt <= $MAX_NUM_THREADS; $tt+=$THREAD_STEP){
	    if($tt == 0){
		$t=1; 
	    }
	    else{
		$t = $tt; 
	    }
	    $current_time=0;
	    
	    my $command_line = $command_line_pattern;
	    $command_line =~ s/NBTHREADS/$t/;
	    $command_line =~ s/DATASET/$DATASET_FILE[$ds]/;
	    $command_line =~ s/SUP/$DATASET_SUP[$ds]/;
	    
	    $bin2 = $bin; 
	    $bin2 =~ s/NBTHREADS/$t/;
	    print OUTPUT "$t "; 

	    if($par or $wallclock_time == -1){
		$wallclock_time = run_child("$command_line", $bin2, $t); 

		if($wallclock_time == -1){
		    print OUTPUT "ERR ERR"; 
		}
		else{
		    #extract time from output
		    my $time = &$extract_time_func("out_tmp"); 
		    print OUTPUT $wallclock_time." ".$time;
		    #print OUTPUT $wallclock_time;
		}
	    }
	    else{
		print OUTPUT $wallclock_time." ".$time;
	    }
	    print OUTPUT "\n"; 

	    system ("cp out_tmp $OUTPUTDIR/dumps/".$name.'_'.$t.'_'.$DATASET_NAME[$ds].'@'.$DATASET_SUP[$ds]);
	    
	}
	close OUTPUT; 
	close MEM; 
    }
}


sub print_usage{
    print STDERR "Usage : $_[0] <dataset1\@support1> ... <algorith_1_name> ... [-t <min_thread>] [-T <max thread>] [-n]\n" ;
	exit 0; 
}




use Getopt::Std;
my %opts;

$config_loaded = 0; 
@runs =(); 


%vars; 

while ($arg = shift){
    if($arg =~ /\-([vc])/){
	if($1 eq 'v'){
	    # parse a var argument
	    # creates a var entry with a list of values for this var
	    if(defined($var = shift)){
		$vars{$var} = ();
		while(defined ($n = shift @ARGV)){
		    if($n =~ /^-/){
			unshift @ARGV, $n; 
			last; 
		    }
		    push @{$vars{$var}}, $n; 
		}
		print_usage if ($#{$vars{$var}} == 0); 
	    }
	    else{
		print_usage; 
	    }
	}
	else{
	    print_usage; 
	}
    }
    else{
	# parse the command to execute (so far a command can be
	# anything)
	if($arg =~ /(.*)/){
	    $command = $arg
	}
    }
}


foreach $var (keys %vars){
    foreach $value (@{$vars{$var}}){
	print "VAR $var : $value\n";
    }
    
}
print "PARSED COMMAND $command\n"; 


#load default config file "run_config.pl" if no other config file has been loaded.
if(not $config_loaded){
    do "./run_config.pl" or die $!;
    print STDERR "Loaded default config file run_config.pl\n";
}



# Premliminaries checks, hopefully those will detect erroneous parameters. 
foreach $run (@runs){
	if(exists($bin{$run})){
	    $bin{$run}{run} = 1;
	    (-x $bin{$run}{bin}) or die "Binary file \'$bin{$run}{bin}\' for \'$run\' does not exists or is not executable.\n";
	}
	else{
	    print STDERR "\'$run\' is not available, check your config file!\ Aborting.\n";
	    die; 
	}
}


foreach $run (keys %bin){
    %bin_info = %{$bin{$run}};
    if($bin_info{run}){
	run($run, $bin_info{bin}, $bin_info{command}, 
	    $bin_info{time_func}, $bin_info{par});
    }
}
print "END : ".date_string."\n";
