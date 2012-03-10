#!/usr/bin/perl  
#use strict; 

my $debug=0 ;



$MIN_NUM_THREADS=1;
$MAX_NUM_THREADS=2;
$THREAD_STEP=1;
$NUM_THREADS=$MAX_NUM_THREADS; # deprecated

$NO_OUTPUT_FILE = 0; 

$DATA_DIR = 'DATA/';
$DATASET_EXT = '.dat';

my $timeout = -1; #In number of cycles, -1 is unlimited
my $max_mem_usage = -1; #In kiB -1 is unlimited
my $total_memory; 


my $child_pid=-1; 
my $current_time = 0; 
my $current_process_name; 

$CYCLE_LEN=1; #in sec. must be 60





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


# Warning: may die; 
sub get_total_memory{
    die if @_ != 0; 
    
    open MEMINFO, "/proc/meminfo" or die $!; 
    while (my $line = <MEMINFO>){
	if($line =~ /MemTotal.*?([0-9]+).*/){
	    close MEMINFO; 
	    return $1; 
	}
    }
    die "Error: Cannot find out total memory.\n";
}

sub check_memory_usage{
    die if @_ != 0;
    return 0 if($max_mem_usage == -1); 
    open INPUT, 'ps -eo comm,rss | awk \'/'.$current_process_name.'/ && !/awk/ {print $2}\'|'; 
    my $mem = <INPUT>;
    close INPUT;
    print MEM "$current_time $mem"; 
    if($mem >= $max_mem_usage){
	print STDERR "Process $current_process_name uses more than $max_mem_usage kiB : $mem\n"; 
	return 1; 
    }
    else {
	return 0; 
    }
}

sub check_timeout{
    die if @_ != 0; 
    return 0 if($timeout == -1);
    
    if($current_time >= $timeout){
	print STDERR "Process $current_process_name have been running for longer that $timeout\n"; 
	return 1; 
    }
    return 0; 
}

sub run_child{
    die if (@_ != 1); 
    my $command = $_[0];
    
    $current_process_name = extract_process_name($command);
    $current_time = 0; 
    my $child_pid = fork;
    if (not $child_pid) {
	not $NO_OUTPUT_FILE and print "exec : $command (timout : ".$timeout.")\n"; 
	
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
#     $SIG{ALRM} = sub { print "KILLING $child_pid\n"; kill 15, $child_pid or kill 9, $child_pid or print  "WARNING could not kill child process $child_pid.\n"; print STDOUT "killed $child_pid after $timeout s\n";   };
#     alarm($timeout);
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
    print STDERR "Usage: $_[0] <dataset1\@support1> ... <algorith_1_name> ... [-t <min_thread>] [-T <max thread>] [-n]\n" ;
    exit 0; 
}




my %opts;

$config_loaded = 0; 
@runs =(); 


my %params;
my $progtotest_command_template;
my @parameters_value_space; 
my @parameters_name; 
my @progtotest_command_lines; 

init(); 
parse_program_arguments(\@ARGV);
check_progtotest_command_template(); 
build_progtotest_command_lines();
print_info(); 
run_command_lines(); 


sub print_info(){
    die if @_ != 0;


    if ($timeout == -1){ print "Timeout:\tUnlimited.\n"; }
    else { print "Timeout:\t$timeout (min)\n";}

    print "Total memory:\t".($total_memory/1024)." MiB\n"; 
    if ($max_mem_usage == -1){ print "Max memory usage:\tUnlimited.\n"; }
    else { print "Max memory usage:\t".($max_mem_usage/1024)." MiB\n";}
    
    print "The following command lines will be executed:\n"; 
    print_progtest_command_lines();



}

sub extract_process_name{
    die if @_ != 1; 
    my ($command) = @_;
    my $process_name = "unknwown_process"; 

    if( $command =~ /.*?\/?([\w\-]+)\s/gx){
	$process_name = $1;
    }
    else {
	print STDERR "Error : cannot parse process name \n"; 
    }
    return $process_name; 
}

sub run_command_lines{
   foreach my $cl (@progtotest_command_lines){
       run_child($cl);
    }
}



sub print_progtest_command_lines{
    foreach my $cl (@progtotest_command_lines){
	print ">>$cl<<\n"; 
    }
}

sub build_progtotest_command_lines{
    die if @_ != 0; 
    
    @parameter_names =  @{shift @parameters_value_space};
    foreach my $tuple (@parameters_value_space){
	my $command_line = $progtotest_command_template; 
	for my $i (0 .. $#$tuple){
	    die unless ($command_line =~ s/$parameter_names[$i]/@{$tuple}[$i]/)
    	}
	push @progtotest_command_lines, $command_line;
    }

}

sub check_progtotest_command_template{
    foreach my $param (keys %params){
	if($progtotest_command_template =~ /$param/){
#	    print "Found param \'$param\'$ in command line template.\n"; 
	}
	else{
	    print STDERR "Warning: param \'$param$\' not found in command line template.\n"; 
	}
    }
}



sub init{
    die if @_ != 0; 

# memory 
    $total_memory = get_total_memory(); 

# initialize timer for the control loop
    $SIG {ALRM} = sub {
	$current_time++; 
	if(check_memory_usage or check_timeout){
	    print STDERR "killing $current_process_name\n"; 
	    do{
		system("killall -9 $current_process_name\n");  
		sleep(1); 
	    }
	    while($_); 
	}
	else {
	    alarm $CYCLE_LEN;
	}
    };

}

sub parse_program_arguments{
    $#_ == 0 or die "Unexpected argument number.\n"; 
    my @argv = @{$_[0]}; 

    while (my $arg = shift @argv){
	if($arg =~ /\-([putm])/){

	    ####################
	    #### parameters ####
	    ####################
	    if($1 eq 'p'){
		# parse a param argument
		# creates a param entry with a list of values for this param
		if(defined(my $param = shift @argv)){
		    if(not $param =~ /[a-zA-Z_][a-zA-Z_0-9]*/){
			print STDERR "Error: Unexpected parameter name \'$param\'.\n";
			print_usage; 
		    }
		    
		    $params{$param} = ();
		    while(defined ($n = shift @argv)){
			if($n =~ /^-/){
			    unshift @argv, $n; 
			    last; 
			}
			push @{$params{$param}}, $n; 
		    }
		    print_usage if ($#{$params{$param}} == 0); 
		}
		else{
		    print_usage; 
		}
	    }

	    ###############
	    #### using ####
	    ###############
	    elsif($1 eq 'u'){
		if(defined(my $param = shift @argv)){
		    require Using;
		    Using::init_parser(); 
		    foreach my $param_name (keys %params){
			Using::add_parameter_value_space($param_name, $params{$param_name}); 
		    }

		    @parameters_value_space = Using::parse($param);
		}
		else{
		    print_usage;
		}
	    }

	    #################
	    #### timeout ####
	    #################	    
	    elsif($1 eq 't'){
		if(defined(my $param = shift @argv)){
		    $timeout = $param; 
		}
		else{
		    print_usage; 
		}
	    }

	    ######################
	    #### memory limit ####
	    ######################	    
	    elsif($1 eq 'm'){
		if(defined(my $param = shift @argv)){
		    $max_mem_usage = $param * $total_memory / 100; 
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
		$progtotest_command_template = $arg
	    }
	}
    }
}

print "END : ".date_string."\n";
