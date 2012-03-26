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

sub date_string_ymd{
    use POSIX qw/strftime/;
    return strftime('%F',localtime); 
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
	not $NO_OUTPUT_FILE and print "exec : $command (timeout: ".$timeout.")\n"; 
	
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
    chop $time; 
    close TIME; 
    not $NO_OUTPUT_FILE and print "Run time : ".($time)."\n";
    
    return $time; 
}

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
my @parameter_index_order; 
my %parameter_values; # bind parameter actual values to indices. 
init(); 
parse_program_arguments(\@ARGV);
check_progtotest_command_template(); 
build_progtotest_command_lines();
print_info(); 
run_command_lines(); 



sub print_file_header{
    print OUTPUT "# Overall experiment start at $START_TIME on $hostname\n";
    print OUTPUT "# Date : ".date_string()."\n";
    print OUTPUT "# nb_threads in [$MIN_NUM_THREADS, $MAX_NUM_THREADS].\n";
    print OUTPUT "# file $bin (MD5 : $md5).\n";
    print OUTPUT "#\n# <nbthreads> <wallclock time> <usertime>\n";

    # print MEM "# Overall experiment start at $START_TIME on $hostname\n";
    # print MEM "# Date : ".date_string()."\n";
    # print MEM "# nb_threads in [$MIN_NUM_THREADS, $MAX_NUM_THREADS].\n";
    # print MEM "# file $bin (MD5 : $md5).\n";
    # print MEM "#\n# <cylce id($CYCLE_LEN)> <mem usage (kiB)>\n";
}	    


# Print system info and so on. 
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

# Extract process name from a command line. 
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


# Comparaison operator used for sort_tuples. 
sub compare_tuples{
    die if @_ != 2; 
    my ($t1_ref, $t2_ref) = @_; 

    foreach $i (@parameter_index_order){
	return 1  if(@{$t1_ref}[$i] lt @{$t2_ref}[$i]);
	return -1 if(@{$t1_ref}[$i] gt @{$t2_ref}[$i]);
    }
    return 0; 
}

# Sort tuples in the fcl order.  The fcl (file, column, line) groups
# together the tuples that have the same value on an 'f' parameter,
# then the ones that have the same value on a 'l' parameter and so on. 
#
# Useful to group the execution that output in the same file. 
sub sort_tuples{
    die if @_ == 0;
    my @tuples = @_;
    
    # Compute parmeter orders to execute commands to the same file first. 
     @parameter_index_order = compute_flc_order(); 

    @tuples = sort { compare_tuples($a, $b) } @tuples; 
    return @tuples; 
}


sub start_file{
    die if @_ != 1; 
    my ($filename) = @_;
    
    open OUTPUT, ">$filename" or print STDERR "Error: Cannot create file \'$filename\'\n";
    print_file_header(); 
}


sub end_file{
    print OUTPUT "\n####\n"; 
#    close OUTPUT; 
}


sub start_line{
    die if @_ != 1; 
    my ($line_head) = @_; 
    print OUTPUT $line_head;
    shift_column(); 
}

sub end_line{
    print OUTPUT "\n"; 
}

sub shift_column{
    print OUTPUT "\t"; 
}

sub create_dat_filename{
    die if @_ < 1; 
    my @tuple = @_;
    $filename = date_string_ymd();
    
    my @parameters_names = @{$parameters_value_space{names}}; 
    my @parameters_decors = @{$parameters_value_space{decors}}; 

    foreach my $i (@parameter_index_order){
	if($parameters_decors[$i] eq 'f'){
	    my $value = $parameter_values{$parameters_names[$i]}->[$tuple[$i]]; 
	    $filename .= '.'.$parameters_names[$i].'-'.$value;
	}
	else{
	    $filename .= '.'.$parameters_names[$i]; 
	}
    }
    print "FILENAME $filename\n"; 
    return $filename.'.dat'; 
}

sub get_parameter_value{
    die if @_ != 2; 
    my ($name, $index) = @_; 
    return $parameter_values{$name}->[$index];
}

sub run_command_lines{
    die if @_ != 0;
    my @parameters_names = @{$parameters_value_space{names}}; 
    my @parameters_decors = @{$parameters_value_space{decors}}; 
    
# A tuple is a possible set of parameter values in the parameter value space. 
    my $previous_tuple = -1; 
    my $filename; 

    my $tuple;
    foreach  $tuple (sort_tuples @{$parameters_value_space{values}}){
	# loop over the parameter values flc order
	foreach my $v (@parameter_index_order){
	    if(not $tuple->[$v] eq $previous_tuple->[$v]){
		if($parameters_decors[$v] eq 'f'){
		    # f decored parameter takes a new value => create a new file
		    end_file() if ($previous_tuple != -1);
		    start_file(create_dat_filename(@$tuple));
		}

		elsif($parameters_decors[$v] eq 'l'){
		    # l decored parameter takes a new value => create a new line
		    end_line() if ($previous_tuple != -1);
		    start_line(get_parameter_value($parameters_names[$v], $tuple->[$v]));
		}
		else{
		    # c decored parameter takes a new value => create a new column
		    shift_column();
		}
	    }
	}

	 my $cl =  build_progtotest_command_line($progtotest_command_template, @{$tuple}); 
	 print OUTPUT run_child($cl);

	 $previous_tuple = $tuple; 
    }

#    unless ($previous_tuple == -1){shift_column(); end_line(); end_file(); }


    
}



sub print_progtest_command_lines{
    foreach my $cl (@progtotest_command_lines){
	print ">>$cl<<\n"; 
    }
}

# Return an array of indexes in parameters names array so that any
# parameter name with a 'f' decor occurs before any parameter name
# with a 'l' decor and any parameter name with a 'l' decor occurs
# before any parameter name with a 'c' decor. 
sub compute_flc_order{
    die if @_  != 0;
    my @order; 
    my @parameter_names =  @{$parameters_value_space{names}};
    my @parameter_decors =  @{$parameters_value_space{decors}};

    for my $pi (0..$#parameter_names){
	if($parameter_decors[$pi] eq "f"){
	    push @order, $pi; 
	}
    }
    for my $pi (0..$#parameter_names){
	if($parameter_decors[$pi] eq "l"){
	    push @order, $pi; 
	}
    }
    for my $pi (0..$#parameter_names){
	if($parameter_decors[$pi] eq "c"){
	    push @order, $pi; 
	}
    }

    # print "MY ORDER \n"; 
    # foreach $v(@order){
    # 	print "$v "; 
    # }
    # print "\n";
    return @order; 
}


# Build a command line from a parameter tuples.
# Substitutes parameter names by corresponding values in the tuples. 
sub build_progtotest_command_line{
    die if @_ < 2;
    my ($command_line_template, @tuple) = @_;

    my @parameter_names =  @{$parameters_value_space{names}};
    
    my $command_line = $progtotest_command_template;
    for my $i (0..$#tuple){
	unless ($command_line =~ s/$parameter_names[$i]/$parameter_values{$parameter_names[$i]}->[$tuple[$i]]/){
	    die "Cannot subtitute parameter \'$parameter_names[$i]\' by value \'$parameter_values{$parameter_names[$i]}->[$tuple[$i]]\' in command line template \'$progtotest_command_template\'.";
	}
	
    }
    return $command_line; 
}


sub build_progtotest_command_lines{
    die if @_ != 0; 
  
    foreach my $tuple (sort_tuples @{$parameters_value_space{values}}){
	push @progtotest_command_lines, build_progtotest_command_line($progtotest_command_template, @{$tuple});
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

# records a new parameter and its possible values
sub add_parameter_values{
     die if @_ != 2; 
     my ($p_name, $value_space_ref) =  @_; 
     $parameter_values{$p_name} = $value_space_ref; 
     Using::add_parameter_range($p_name, $#{$value_space_ref}+1); 
}

sub parse_program_arguments{
    $#_ == 0 or die "Unexpected argument number.\n"; 
    my @argv = @{$_[0]}; 

    while (my $arg = shift @argv){
	if($arg =~ /\-([putm-])/){

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
		    print_usage if (@{$params{$param}} == 0); 
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
			add_parameter_values($param_name, $params{$param_name}); 
		    }

		    %parameters_value_space = Using::parse($param);
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
	    
	    elsif($1 eq '-'){
		if(@argv == 0) {print_usage; die "Cannot parse command line\n";}
		
		$progtotest_command_template = join(' ',@argv)."\n";
		@argv=(); 
	    }
	    else{
		print_usage; 
		die; 
	    }

	}
    }
}


print "END : ".date_string."\n";
