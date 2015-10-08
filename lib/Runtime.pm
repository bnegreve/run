# Copyright (C) 2010-2013, Benjamin Negrevergne.
package Runtime;
use 5.012; 
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(startup);

our $VERSION = '0.01';

use File::Basename;
use File::Copy; 
use Using;
use Using_Ast_Check;
use Result_Db;
use System_API;

use vars qw(%parameter_value_space);

our $using_ast; 


my $LINE_RESULT_SEPARATOR = "\n"; 
my $COLUMN_RESULT_SEPARATOR = "\t"; 
# In case there are multiple parameters with the same format spec, how to deparate them.
# e.g. AfxBcxClxDl,
my $CELL_RESULT_SEPARATOR = ':'; 

my $timeout = -1; #In sec, -1 is unlimited
my $mem_usage_cap = -1; #In kiB -1 is unlimited
my $total_memory; 


my $child_pid=-1; 
my $current_time = 0; 
my $current_process_name;
my $current_process_pid;
my $current_process_err;

my $CYCLE_LEN=1; #in sec. 
my $START_TIME = date_string();

my %opts;

my @runs =(); 


my $output_dir;
my $tmp_out; # temporary out file.
my $time_tmp_file; # temporary out file for time process
my @post_exec_scripts; # user scripts to extract metrics
#my $current_bin_filename; 
my %params;
my $progtotest_command_template;
my @progtotest_command_lines; 

my $dryrun = 0;

our $runtime_bin_path = $0; 

our $errors = 0; 

sub error_args{
    die if @_ != 1; 
    print STDERR 'Error while parsing Runtime arguments: '.$_[0]."\n"; 
    $errors++;
    print "\n"; 
    print_usage();
    exit(1); 
}

sub error_check{
    die if @_ != 1; 
    print STDERR 'Error while checking experiment settings: '.$_[0]."\n"; 
    $errors++;
    print "\n"; 
    print_usage();
    exit(1); 
}


sub warning_output{
    die if @_ != 1; 
    print STDERR 'Warning, while writing result files: '.$_[0].".\n"; 
    $errors++;
}

sub warning_build_command_line{
    die if @_ != 1; 
    print STDERR 'Warning while building command line: '.$_[0]."\n";
    $errors++;
}

sub run_child{
    die if (@_ != 1); 
    my $command = $_[0];

#    $current_bin_filename = extract_bin_filename($command);
    $current_process_name = extract_process_name($command);
    $current_time = 0; 
    $current_process_err = "ERR_UKN";
    my $child_pid = fork;
    $current_process_pid = $child_pid;
    reset_memory_usage(); 

    if (not $child_pid) {
	print "Executing: $command\n";
	exec "/usr/bin/time -o $time_tmp_file -f \"%e\" $command 2>&1 > $tmp_out " or die "command failed\n"; 
    }


    alarm $CYCLE_LEN;
    waitpid($child_pid, 0); 
    alarm 0;
    if($? != 0){
	unlink $time_tmp_file;
	unlink $tmp_out;
	return  ($current_process_err, $current_process_err, ($current_process_err) x @post_exec_scripts); 
    }
    
    my $time;
    open TIME_TMP, "$time_tmp_file" or die "cannot open time file\n";
    $time = <TIME_TMP>; 
    chop $time; 
    close TIME_TMP; 
    unlink $time_tmp_file;
    print "Run time : ".($time)." sec.\n";

    my $mem = (get_memory_usage())/1024; 

    # executing post execution scripts
    my @pes_outputs = (); 
    for my $script (@post_exec_scripts){
	my $pes_output;
	if(open(POST_EXEC_OUT,"-|", "cat $tmp_out | $script")){
	    if(not defined($pes_output = <POST_EXEC_OUT>)){
		 print STDERR "Warning: cannot read first line of output generated by user script \'$script\'".$!."\n";
		 $pes_output = "ERR"; 
	    }
	    print "User script output ($script): $pes_output\n"; 
	    chop $pes_output;
	    push @pes_outputs, $pes_output;
	    close(POST_EXEC_OUT); 
	} 
	else{
	    print STDERR "Warning: cannot run post exec user script \'$script\': ".$!.".\n"; 
	}
    }
    
    return ($time, $mem, @pes_outputs); 
}


# print a description in the file handled by fh
# bin is the binary file name executed
# info reported is a string describing what is reported, e.g. time. 
sub print_file_header{
    die if @_ != 4; 
    my ($fh, $tuple, $bin, $info_reported) = @_; 
    my $md5 = md5_file($bin); 
    my $hostname = get_hostname(); 

    my $date = date_string();
        my $header_string = <<END;
# File: @{[tuple_to_result_filename($tuple)]} 
# Experiment started on: @{[date_string()]}. 
# Machine hostname: $hostname.
# Timout for each run $timeout s.  
# Maximum memory usage allowed @{[$mem_usage_cap/1024]} MiB.
#
# Reporting: $info_reported.
#
END
    print $fh $header_string;
}


sub print_progtest_command_lines{
    foreach my $cl (@progtotest_command_lines){
	print "\t$cl\n"; 
    }
}


# Print system info. 
sub print_info(){
    die if @_ != 0;

    if ($timeout == -1){ print "Timeout:\tUnlimited.\n"; }
    else { print "Timeout:\t$timeout (sec)\n";}

    print "Total memory:\t".($total_memory/1024)." MiB\n"; 
    if ($mem_usage_cap == -1){ print "Max memory usage:\tUnlimited.\n"; }
    else { print "Max memory usage:\t".($mem_usage_cap/1024)." MiB\n";}
}


sub output_dir_default_name{
    die if @_ != 0; 
    my $output_dir = date_string().'/';

    $output_dir =~ s/ /_/g; 
    $output_dir =~ s/://g;

    return $output_dir; 
}


# userscript full filename to binary name
sub scriptpath_to_scriptname{
    die if @_ != 1;
    my ($path) = @_; 
    my $name = fileparse($path, qw(.sh .bash .pl));
    return $name; 
}

# check whether a userscript correct or not (i.e. exists and is executable). If it is, returns non null. 
sub check_script{
    die if @_ != 1; 
    my ($scriptpath) = @_;
    return 1 if -x $scriptpath; 
    return 0; 
}

# check the script list, generate errors if there is a problem with one script or more. 
sub check_all_scripts{
    my @all_scripts = @_;
    my %all_basenames = ();
    for my $script(@all_scripts){
	error_check("Script '$script' does not exist or is not executable.") if check_script($script) != 1; 
	
	my $basename = scriptpath_to_scriptname $script;
	if (not exists($all_basenames{$basename})){
	    $all_basenames{$basename} = $script; 
	}
	else{
	    my $other = $all_basenames{$basename}; 
	    error_check("Script '$other' and script '$script' have the same basename (and it is not allowed).");
	}
    }
}

sub init_temp_file{
    die if @_ != 0;
    my $out_fh; 
    ($out_fh, $tmp_out) = create_temp_file("tmp");
    close($out_fh);
    ($out_fh, $time_tmp_file) = create_temp_file("tmp_time");
    close($out_fh); 
}

sub init{
    die if @_ != 0; 

# memory 
    $total_memory = get_total_memory(); 

# initialize timer for the control loop
    $SIG {ALRM} = sub {
	$current_time+=$CYCLE_LEN; 
	my $mu = check_memory_usage($current_process_pid, $mem_usage_cap);
	my $tu = check_timeout($current_time, $timeout);

	if($mu or $tu){
	    if($mu) {
		print STDERR "Process $current_process_name uses more than $mem_usage_cap kiB : ".get_memory_usage()."\n"; 
	    }

	    if($tu) {
		print STDERR "Process $current_process_name have been running for longer that $timeout sec (+- $CYCLE_LEN sec)\n"; 
	    }

	    print STDERR "killing $current_process_name.\n";
	    kill_process_tree($current_process_pid);
	    if($mu){
		$current_process_err = "ERR_MEM"; 
	    }
	    else{
		$current_process_err = "ERR_TME"; 
	    }

	    sleep(1); 
	}
	else {
	    alarm $CYCLE_LEN;
	}
    };

    $output_dir = output_dir_default_name();
    
# preparing tmp file to store program outputs.
    init_temp_file(); 
}

sub create_readme_file{
    die if @_ < 1; 
    my @argv = @_;
    open README, ">$output_dir/README.tmp" or die $!;

    print README "\n###########################\n";
    print README "Experiment started at $START_TIME on ".get_hostname().".\n";
    print README "$0 ".join(' ',@argv)."\n";
    
    print README "\n\n";
    print README "Executed:\n";
    foreach my $cl (@progtotest_command_lines){
	print README "\t$cl\n"; 
    }    
    print README "\n"; 

    close README; 
 }

sub finalize_readme_file{
    die if @_ != 0;
    open README, ">>$output_dir/README" or die $!;
    open READMETMP, "$output_dir/README.tmp" or die $!;
    print README "\n\n"; 

    while (my $line = <READMETMP>){
	print README $line; 
    }
    close READMETMP;
    print README "Expeperiment finished at ".date_string()."\n";
    close README;
    system ("rm -f $output_dir/README.tmp"); 
    
}

# Create all the directories and the files in the output dir. 
sub populate_output_dir{
    die if @_ != 1; 
    my ($output_dir) = @_;

    system("mkdir -p $output_dir/"); 
    system("mkdir -p $output_dir/time"); 
    system("mkdir -p $output_dir/mem"); 
    system("mkdir -p $output_dir/output");

    for my $script (@post_exec_scripts){
	my $scriptname = scriptpath_to_scriptname $script; 
	system("mkdir -p $output_dir/$scriptname"); 
    }
}

sub print_usage{
    die if @_ != 0; 
    print STDERR "Usage: $runtime_bin_path -p PARAMETER_NAME parameter_value_1 .. parameter_value_n\
 [-p PARAMETER2_NAME parameter2_value_1 .. parameter2_value_n]\
 [-s extract_metric_script1 [-s extract_metric_script2 ...]\
 [-m max_memory_usage (% total)] [ -t timeout value] [ -d (dryrun) ]\
 -u using_expression -- command_line_template\n";
 
    exit 0; 
}


sub parse_program_arguments{
    $#_ == 0 or die "Unexpected argument number.\n"; 
    my @argv = @{$_[0]}; 

    while (my $arg = shift @argv){
	if($arg =~ /\-([putmsod-])/){

	    ####################
	    #### parameters ####
	    ####################
	    if($1 eq 'p'){
		# parse a param argument
		# creates a param entry with a list of values for this param
		if(defined(my $p_name = shift @argv)){
		    if(not $p_name =~ /[a-zA-Z_][a-zA-Z_0-9]*/){
			error_args "Parameter '$p_name' is not a valid parameter name (parameter names must match [a-zA-Z_][a-zA-Z_0-9]*.";
		    }
		    
		    my @values = (); 
		    while(defined (my $n = shift @argv)){
			if($n =~ /^-[^0-9]/){
			    unshift @argv, $n; 
			    last; 
			}
			push @values, $n; 
		    }
		    if(@values != 0){
			declare_parameter($p_name, @values); 
		    }
		    else{
			error_args "No value provided for parameter '$p_name'.";
		    }
		}
		else{
		    print_usage(); 
		}
	    }

	    ###############
	    #### using ####
	    ###############
	    elsif($1 eq 'u'){
		if(defined(my $param = shift @argv)){
		    foreach my $param_name (keys %params){
			declare_parameter($param_name, $params{$param_name}); 
		    }

		    $using_ast = Using::parse($param);
		}
		else{
		    print_usage();
		}
	    }

	    #################
	    #### timeout ####
	    #################	    
	    elsif($1 eq 't'){
		if(defined(my $param = shift @argv)){
		    $timeout = $param; 
		    if($timeout <= $CYCLE_LEN){
			print STDERR "Warning: timout value ($timeout sec) is below timeout resolution ($CYCLE_LEN sec).\n"; }
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
		    $mem_usage_cap = $param * $total_memory / 100; 
		}
		else{
		    print_usage; 
		}
	    }


	    ##########################
	    #### post exec script ####
	    ##########################	    
	    elsif($1 eq 's'){
		if(defined(my $param = shift @argv)){
		    push @post_exec_scripts, $param;

		}
		else{
		    print_usage; 
		}
	    }

	    #################################
	    #### use existing output dir ####
	    #################################	    
	    elsif($1 eq 'o'){
		if(defined(my $param = shift @argv)){
		    $output_dir = $param.'/';
		}
		else{
		    print_usage;
		}
	    }

	    #################
	    #### dry run ####
            #################
	    elsif($1 eq 'd'){
		$dryrun = 1; 
	    }

	    elsif($1 eq '-'){
		if(@argv == 0) {print_usage; die "Cannot parse command line\n";}
		
		$progtotest_command_template = join(' ',@argv);
		@argv=(); 
	    }
	    else{
		print_usage;
		die; 
	    }

	}
    }
    
    if(not defined $progtotest_command_template){
	error_args("No command template provided: providing a command template is mandatory."); 
    }

    if(not defined $using_ast){
	error_args("No using expression provided (-u): providing a using expression is mandatory."); 
    }

}


# Build a command line from the command line template and a tuple of
# value references.
#
# Iterate through the template and replace occurrences of PNAME with
# value refered by the first value reference <PNAME, value_index>.
# Warning: If the same PNAME occurs multiple times, each occurrence is
# only replaced once for each value reference (left-most occurrences
# are replaced first.)
sub build_a_command_line{
    die if @_ != 2; 
    my $template = $_[0];
    my @tuple = @{$_[1]}; 

    foreach my $vr(@tuple){
	my $pname = value_ref_get_pname($vr);
	my $value = value_ref_get_value($vr);

	if(not ($template =~ s/$pname/$value/)){
	    warning_build_command_line
		"Parameter '$pname' not found in command line template."; 
	}
    }
    return $template;     
}

# Create a filename from a tuple. 
# (To store results.)
sub tuple_to_result_filename{
    die if @_ != 1; 
    my ($tuple) = @_;
    my $string = "";
    my $i = 0; 
    foreach my $vr (@{$tuple}){
	#print(Using_Ast_Check::parameter_value_ref_to_string($vr)."\n");
	my $pname = value_ref_get_pname($vr);
	my $param_id = value_ref_get_param_id($vr); 
	$string .= $pname; 
	if(Using_Ast_Check::parameter_get_format_spec($param_id) eq 'f'){
	    $string .= '.'.value_ref_get_value($vr);
	}
	if(++$i != @{$tuple}){
	    $string .= '_';
	}
    }
    return $string; 
}

# Create a filename from a tuple. 
# (To store the program output.)
sub tuple_to_output_filename{
    die if @_ != 1; 
    my ($tuple) = @_;
    my $string = "";
    my $i = 0; 
    foreach my $vr (@{$tuple}){
	#print(Using_Ast_Check::parameter_value_ref_to_string($vr)."\n");
	my $pname = value_ref_get_pname($vr);
	my $param_id = value_ref_get_param_id($vr); 
	$string .= $pname; 
	$string .= '.'.value_ref_get_value($vr);
	if(++$i != @{$tuple}){
	    $string .= '_';
	}
    }
    return $string; 
}

sub save_program_output{
    die if @_ != 1; 
    my ($tuple) = @_;
    my $filename = "$output_dir/output/".tuple_to_output_filename($tuple).".out";
    move($tmp_out, $filename);
}

# Returns a class specification from a tuple. A class specification is
# also a tuple in which only class relevant parameters their
# values are preserved. A tuple belongs to a class if all the values
# that occurs in the class spec match the values in the tuple.
#
# For example [ <:> <B:2> <:> ] is a possible class spec and the tuples:
#  [ <A:1> <B:2> <C:3> ] and [ <A:3> <B:2> <C:17> ] both belong to the
#  class defined by the class spec.
#
# There are three types of class, one f (for file) class type for the
#  class of tuples refers values that have to be stored in the same
#  file, one c class type (for column) and one l class type for
#  (line).
# 
sub tuple_to_class_spec{
    die if @_ != 2;
    my ($tuple, $class_type) = @_;  

    my @class_spec = (); 
    foreach my $vr (@$tuple){
	if(parameter_get_format_spec(value_ref_get_param_id($vr)) 
	   eq $class_type){
	    push @class_spec, $vr; 
	}
	else{
	    push @class_spec, ["","",""];
	}
    }

    return \@class_spec; 
}

# Given a set of tuples and a class spec (see tuple_to_class_spec),
# returns all the tuples that belong to the class described by class
# spec.
sub get_class_from_class_spec{
    die if @_ != 2; 
    my ($all_tuples, $class_spec) = @_;
    my @class = (); 
    
    foreach my $t (@$all_tuples){
	my $same_class_flag = 1; 
	for(my $i = 0; $i < @$t; $i++){
	    if(value_ref_get_pname($class_spec->[$i]) ne ""){
		if(value_ref_get_value($class_spec->[$i]) ne 
			value_ref_get_value($t->[$i])){
		    $same_class_flag = 0;
		    last; 
		}
	    }
	}
	if($same_class_flag == 1){
	    push @class, $t ; 
	}
    }

    return @class; 
}


# A class is a set of tuples that have the same value on a set of
# parameter.  class type is either f c l, if class_type is f, the
# function will return all the tuples that belong to the same file.
# i.e. that have the same value on all the parameter with a f format
# string.
sub get_all_classes_from_class_type{
    die if @_ != 2; 
    my ($all_tuples, $class_type) = @_; 
    
    my @all_classes = ();
    my %class_index = (); # to compute class indexes
    
    foreach my $t (@$all_tuples){
	my @class_spec = @{tuple_to_class_spec($t, $class_type)}; 
	my $class_spec_string = tuple_to_string(\@class_spec);

	my $i = $class_index{$class_spec_string};
	if(not defined $i){
	    # first instance of the class, attribute an index.
	    $i = @all_classes; 
	    $class_index{$class_spec_string} = $i;
	    $all_classes[$i] = []; 
	}
	push @{$all_classes[$i]}, $t; 
    }
    return \@all_classes; 
}

# Given a tuple (usually, the first of a line class of tuples), write
# the line heading for the corresponding class.
# The heading is the values of all the parameters that
# remain constant among all the line. (Usually one.)
sub write_line_head_from_tuple{
    die if @_ != 2; 
    my ($tuple, $fh) = @_;

    my @l_values = get_value_refs_from_format_spec($tuple, 'l');

    foreach my $j (0..$#l_values){
	my $vr = $l_values[$j]; 
	print {$fh} value_ref_get_value($vr);
	print {$fh} $CELL_RESULT_SEPARATOR if($j < $#l_values)
    }
    print {$fh} $COLUMN_RESULT_SEPARATOR; 
}

# Bad code duplication of write_line_head_from_tuple. 
# The only thing that differ is the head formating. 
sub write_column_head_from_tuple{
    die if @_ != 2; 
    my ($tuple, $fh) = @_;

    my @c_values = get_value_refs_from_format_spec($tuple, 'c');

    foreach my $j (0..$#c_values){
	my $vr = $c_values[$j]; 
	print $fh value_ref_get_pname($vr).'='.value_ref_get_value($vr);  
	print {$fh} $CELL_RESULT_SEPARATOR if($j < $#c_values)
    }
    print {$fh} $COLUMN_RESULT_SEPARATOR; 
}

# Given a tuple, and a format spec (f, c or l) returns all the value
# refs that match the format spec
sub get_value_refs_from_format_spec{
    die if @_ != 2; 
    my ($tuple, $format_spec) = @_;

    my @vrefs = (); 
    foreach my $vr (@$tuple){
	if(parameter_get_format_spec(value_ref_get_param_id($vr)) eq $format_spec){
	    push @vrefs, $vr; 
	}
    }
    return @vrefs; 
}

# Given a list of tuples that belong to the same file, print the
# results in lines columns according to the format specified by the
# using expression.  $fh is a file handle to the file in which we want
# to print.  Waring: all the tuples must belong to the same file.
sub write_a_result_file{
    die if @_ != 4; 
    my ($result_db, $file_class_tuples, $file_prefix, $info_reported) = @_;

    my $tuple = $file_class_tuples->[0]; 
    my $filename = $file_prefix.tuple_to_result_filename($tuple);
    my $fh; 
    if(not (open $fh, ">$filename")){
	warning_output("Cannot create result file '$filename': $! Using stdout."); 
	$fh = \*STDOUT; 
    }

    print_file_header($fh, $tuple, "/bin/ls", $info_reported);
    print $fh '# ';
    
    # print first column header ie. parameter names of column parameters
    my @l_vr = get_value_refs_from_format_spec($tuple, 'l');
    foreach my $i (0..$#l_vr){
	print $fh value_ref_get_pname($l_vr[$i]);
	print $fh $CELL_RESULT_SEPARATOR if($i < $#l_vr); 
    }
    print $fh $COLUMN_RESULT_SEPARATOR; 
    
    # print columns headers ie. parameter names of line parameter with their value 
    my $all_c_classes = get_all_classes_from_class_type($file_class_tuples, 'c'); 
    foreach my $c_class (@$all_c_classes){
	my $tuple = $c_class->[0];
	write_column_head_from_tuple($tuple, $fh);
    }
    print $fh $LINE_RESULT_SEPARATOR; 

    # print line headers (i.e. values of column parameters.) and results for this line. 
    my $all_l_classes = get_all_classes_from_class_type($file_class_tuples, 'l'); 
    foreach my $l_class (@$all_l_classes){
	write_line_head_from_tuple($l_class->[0], $fh);
	my $all_c_classes = get_all_classes_from_class_type($l_class, 'c'); 
	foreach my $c_class (@$all_c_classes){
	    foreach my $v (@$c_class){
		print $fh $result_db->get_result($v);
	    }
	    print $fh $COLUMN_RESULT_SEPARATOR; 
	}
	print $fh $LINE_RESULT_SEPARATOR; 
    }
    close $fh; 
}

sub write_result_files{
    die if @_ != 4; 
    my ($tuples, $result_db, $file_prefix, $info_reported) = @_; 
    if($result_db->is_dirty()){    
	my $all_file_classes = get_all_classes_from_class_type($tuples, 'f'); 
	foreach my $f_class (@$all_file_classes){
	write_a_result_file($result_db, $f_class, $file_prefix, $info_reported); 
	}
    }
}


sub finalize{
    unlink $tmp_out; 
    unlink $time_tmp_file; 

    die if @_ != 0;
    finalize_readme_file();
    print "Expeperiment finished at ".date_string()."\n";
    if( not (-e 'last_run') or 
	is_runtime_output_dir("last_run")){
	system('rm -f last_run'); 
	create_link($output_dir, "last_run"); 
    }
    else{
	warning_output("'last_run' exists and does not seem to be a link to a runtime output directory. Link not updated");
    }
}

sub startup{
    my @argv = @_; 
    init(); 
    parse_program_arguments(\@argv);
#    print ast_to_string($using_ast);
    check_ast($using_ast);
    check_all_scripts(@post_exec_scripts); 
#    print ast_to_string($using_ast);

    if($dryrun) {print "Warning: THIS IS A DRYRUN, no output file will be generated.\n";}

# Creates output file and database files


    my $time_db; 
    my $mem_db;
    my %usr_dbs = (); 

    unless ($dryrun){
	populate_output_dir($output_dir);
	
	$time_db = new Result_Db($output_dir, "time");
	$mem_db = new Result_Db($output_dir, "mem");
	%usr_dbs = (); 
	for my $script (@post_exec_scripts){
	    my $scriptname = scriptpath_to_scriptname $script; 
	    my $usr_db = new Result_Db($output_dir, $scriptname);
	    $usr_dbs{$scriptname} = $usr_db; 
	}
    }

# Fetching the tuples and preparing the databses
    my @tuples = @{ast_get_tuples($using_ast)};
    #print Using_Ast_Check::tuples_to_string(\@tuples)."\n"; 
    foreach my $t (@tuples){
	unless ($dryrun) {
	    $time_db->result_db_add_tuple($t);
	    $mem_db->result_db_add_tuple($t);
	    for my $script (@post_exec_scripts){
		my $scriptname = scriptpath_to_scriptname $script;
		$usr_dbs{$scriptname}->result_db_add_tuple($t);
	    }
	}
    }

# Print various info 
    print_info();
    my $num_runs = 0; 
    foreach my $t (@tuples){
	my $cl = build_a_command_line($progtotest_command_template, $t);
	my $outfile = "\t > output/".tuple_to_output_filename($t).'.out';
	push @progtotest_command_lines, $cl.$outfile;
	$num_runs++; 
    }

    print "The following command lines will be executed:\n"; 
    print_progtest_command_lines; 

    if($timeout != -1){
	my $max_run_time = ($num_runs * $timeout) / 60;
	print "Maximum run time: $num_runs x $timeout = $max_run_time minutes. (".($max_run_time/60)." hours.)\n"; 
    }

    
# Everything seems to be OK. Starting experiments.
    if($dryrun){
	print "\nEverything seems to be OK. Exiting now. (Because this is a DRYRUN)\n\n";
	exit(0); 
    }
    else {
	print "\nEverything seems to be OK. Starting experiments.\n";
	print "Results are going to be in $output_dir.\n\n";
    }

    create_readme_file(@argv);

    foreach my $t (@tuples){
	my $cl = build_a_command_line($progtotest_command_template, $t);
	my ($time, $mem, @usr);

	my $skip_flag = 0;
#	print "Search for preceding tuples for: ".tuple_to_string($t)."\n";
	foreach my $p (Using_Ast_Check::get_all_preceding_tuples($t, \@tuples)){
#	    print "PRECEDING TUPLE: ".tuple_to_string($p)."\n";
	    if( ($mem_db->get_result($p) eq "ERR_MEM") or ($time_db->get_result($p) eq "ERR_TME")){
		$skip_flag = 1; 
	    }
	}
	
	if($skip_flag){
	    $time = "SKP"; 
	    $mem = "SKP";
	    @usr = ('SKP') x @post_exec_scripts; 
	    print "Skipping next run because related run timed or memory outed\n\t$cl\n";
	}
	else{
	    ($time, $mem, @usr) =  run_child($cl);
	}
	$time_db->result_db_set_result($t, $time);
	$mem_db->result_db_set_result($t, $mem);
	
	for my $script (@post_exec_scripts){
	    my $scriptname = scriptpath_to_scriptname $script; 
	    $usr_dbs{$scriptname}->result_db_set_result($t, shift @usr); 
	}


	# writing results... after each run for more safety. 
	write_result_files(\@tuples, $time_db,
			   $output_dir.'time/time_', "Wall clock time (in seconds)");
	write_result_files(\@tuples, $mem_db,
			   $output_dir.'mem/mem_', "Max memory usage (in MiB)");
	for my $script (@post_exec_scripts){
	    my $scriptname = scriptpath_to_scriptname $script; 
	    write_result_files(\@tuples, $usr_dbs{$scriptname},
			       $output_dir.$scriptname.'/'.$scriptname.'_',
			       "script output $scriptname ($script)");
	}

	save_program_output($t); 
	init_temp_file(); 

    }

    finalize(); 
}

1;
__END__
