# Copyright (C) 2010-2013, Benjamin Negrevergne.
package Runtime;
use 5.012; 
use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(startup);

our $VERSION = '0.01';



use File::Temp qw/ tempfile/;
use Proc::ProcessTable;

use Using;
use Using_Ast_Check;
use Result_Db;
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
my $post_exec_script_path; 
my $max_mem_usage = 0; 
#my $current_bin_filename; 
my %params;
my $progtotest_command_template;
my @progtotest_command_lines; 

our $errors = 0; 
our $runtime_bin_path = $0; 

sub error_args{
    die if @_ != 1; 
    print STDERR 'Error while parsing Runtime arguments: '.$_[0]."\n"; 
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

sub md5_file{
    die if @_ != 1; 
    my $file = $_[0];
    use Digest::MD5;
    
    my $md5; 
    if(open(FILE, $file)){
    binmode(FILE);
    $md5 = Digest::MD5->new->addfile(*FILE)->hexdigest;
    }
    else{
	warning_output "Cannot compute binary md5 file for '$file': ".$!;
	$md5 = "(Cannot compute md5 for file: '$file')"; 
    }
    return $md5; 
}

sub date_string{
    use POSIX qw/strftime/;
    return strftime('%F %T',localtime); 
}

sub date_string_ymd{
    use POSIX qw/strftime/;
    return strftime('%F',localtime); 
}


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

sub get_process_table{
    die if @_ != 0; 
     return new Proc::ProcessTable;
}


# compute memory of the memory usage .. in kib
sub memory_usage_process_tree{
    die if @_ != 1; 
    my ($pid) = @_;
    my $t = get_process_table;
    
    my $mem = 0; 
    foreach my $p (@{$t->table}) {
	if($p->{"pid"} == $pid){ # found current process
	    $mem += $p->{"rss"} / 1024; # in kib
	}
	
	if($p->{"ppid"} == $pid){ # found child process 
	    $mem += memory_usage_process_tree($p->{"pid"}); 
	}
    }
    
    return $mem; 

}

sub check_memory_usage{
    die if @_ != 0;
    my $mem_usage = memory_usage_process_tree($current_process_pid);

    if($mem_usage > $max_mem_usage){
	$max_mem_usage = $mem_usage; 
    }
    return 0 if($mem_usage_cap == -1); 

    if($mem_usage >= $mem_usage_cap){
	print STDERR "Process $current_process_name uses more than $mem_usage_cap kiB : $mem_usage\n"; 
	return 1; 
    }
    return 0; 
}

sub check_timeout{
    die if @_ != 0; 
    return 0 if($timeout == -1);
    
    if($current_time >= $timeout){
	print STDERR "Process $current_process_name have been running for longer that $timeout sec (+- $CYCLE_LEN sec)\n"; 
	return 1; 
    }
    return 0; 
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
    $max_mem_usage = 0; #reset mem usage 

    if (not $child_pid) {
	print "Executing: $command\n";
	exec "/usr/bin/time -o $time_tmp_file -f \"%e\" $command 2>&1 > $tmp_out " or die "command failed\n"; 
    }


    alarm $CYCLE_LEN;
    waitpid($child_pid, 0); 
    alarm 0;
    if($? != 0){
	return  ($current_process_err, $current_process_err, $current_process_err); 
    }
    
    my $time;
    open TIME_TMP, "$time_tmp_file" or die "cannot open time file\n";
    $time = <TIME_TMP>; 
    chop $time; 
    close TIME_TMP; 
    print "Run time : ".($time)." sec.\n";
    
    # executing post execution script
    my $pes_output; 
    if($post_exec_script_path){
	if(open(POST_EXEC_OUT,"-|", "cat $tmp_out | $post_exec_script_path")){
	    defined($pes_output = <POST_EXEC_OUT>) or print STDERR "Warning: cannot read first line of output generated by user script \'$post_exec_script_path\'".$!."\n";
	    print "PES output $pes_output\n"; 
	    chop $pes_output; 
	    close(POST_EXEC_OUT); 
	} else{
	    print STDERR "Warning: cannot run post exec user script \'$post_exec_script_path\': ".$!.".\n"; 
	}
    }
    return ($time, $max_mem_usage/1024, $pes_output); 
}




sub get_hostname{
    die if @_ != 0; 
    use Sys::Hostname;
    my $hostname = hostname; 
    return $hostname; 
}

# print a description in the file handled by fh
# bin is the binary file name executed
# info reported is a string describing what is reported, e.g. time. 
sub print_file_header{
    die if @_ != 3; 
    my ($fh, $bin, $info_reported) = @_; 
    my $md5 = md5_file($bin); 
    my $hostname = get_hostname(); 

    my $date = date_string();
        my $header_string = <<END;
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
	print ">>$cl<<\n"; 
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
	print STDERR "Error: cannot parse process name \n"; 
    }
    return $process_name; 
}

# Extract bin file name from a command line. 
sub extract_bin_filename{
    die if @_ != 1; 
    my ($command) = @_;
    my $process_name = "unknwown_process"; 

    if( $command =~ /(.*?\/?[\w\-]+)\s/gx){
	$process_name = $1;
    }
    else {
	print STDERR "Error: cannot parse process name \n"; 
    }
    return $process_name; 
}

sub output_dir_default_name{
    die if @_ != 0; 
    my $output_dir = date_string().'/';

    $output_dir =~ s/ /_/g; 
    $output_dir =~ s/://g;

    return $output_dir; 
}


sub kill_process_tree{
    die if @_ != 1; 
    my ($pid) = @_;
    my $t = get_process_table;
    
    foreach my $p (@{$t->table}) {
	if($p->{"ppid"} == $pid){
	    kill_process_tree($p->{"pid"}); 
	}
    }
    kill 9, $pid; 
}

sub init{
    die if @_ != 0; 

# memory 
    $total_memory = get_total_memory(); 

# initialize timer for the control loop
    $SIG {ALRM} = sub {
	$current_time+=$CYCLE_LEN; 
	my $mu = check_memory_usage();
	my $tu = check_timeout(); 
	if($mu or $tu){
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
    (my $out_fh, $tmp_out) = tempfile("/tmp/runtime_tmp_XXXX");
    close($out_fh);
    ($out_fh, $time_tmp_file) = tempfile("/tmp/runtime_tmp_time_XXXX");
    close($out_fh); 

}

sub create_readme_file{
    die if @_ < 1; 
    my @argv = @_;
    open README, ">$output_dir/README.tmp" or die $!;

    print README "\n###########################\n";
    print README "Experiment started at $START_TIME on ".get_hostname().".\n";
    print README "$0 ".join(' ',@argv)."\n";
    
    print README "\n\n"; 
    foreach my $cl (@progtotest_command_lines){
	print README "$cl\n"; 
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
    print README "Expeperiment finished at ".date_string."\n";
    close README;
    system ("rm -f $output_dir/README.tmp"); 
    
}

sub populate_output_dir{
    die if @_ != 1; 
    my ($output_dir) = @_;

    system("mkdir -p $output_dir/"); 
    system("mkdir -p $output_dir/time"); 
    system("mkdir -p $output_dir/mem"); 
    system("mkdir -p $output_dir/output");
    system("mkdir -p $output_dir/usr") if $post_exec_script_path; 
}

sub print_usage{
    die if @_ != 0; 
    print STDERR "Usage: $runtime_bin_path -p PARAMETER_NAME parameter_value_1 .. parameter_value_n\
 [-p PARAMETER2_NAME parameter2_value_1 .. parameter2_value_n]\
 [-s post_output_script] [-m max_memory_usage (% total)] [ -t timeout value]\
 -u using_expression -- command_line_template\n";
 


    exit 0; 
}


sub parse_program_arguments{
    $#_ == 0 or die "Unexpected argument number.\n"; 
    my @argv = @{$_[0]}; 

    while (my $arg = shift @argv){
	if($arg =~ /\-([putmso-])/){

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
			if($n =~ /^-/){
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
		    $post_exec_script_path = $param;

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
sub tuple_to_filename{
    die if @_ != 1; 
    my ($tuple) = @_;
    my $string = "";
    my @file_dims = ast_get_dimension_indexes($using_ast, "f");
    my @cols_dims = ast_get_dimension_indexes($using_ast, "c");
    my @line_dims = ast_get_dimension_indexes($using_ast, "l"); 
    my $total = @file_dims + @cols_dims + @line_dims; 

    my $i = 0; 

    foreach my $d (@file_dims){
	my $vr = $tuple->[$d]; 
	$string .= value_ref_get_pname($vr);
	$string .= '.'.value_ref_get_value($vr);
	if(++$i != $total){
	    $string .= '_';
	}
    }
    foreach my $d (@cols_dims){
	my $vr = $tuple->[$d]; 
	$string .= value_ref_get_pname($vr);
	if(++$i != $total){
	    $string .= '_';
	}
    }
    foreach my $d (@line_dims){
	my $vr = $tuple->[$d]; 
	$string .= value_ref_get_pname($vr);
	if(++$i != $total){
	    $string .= '_';
	}
    }
    return $string; 
}

# Create a filename from a tuple. 
# (To store program output.)
sub tuple_to_output_filename{
    die if @_ != 1; 
    my ($tuple) = @_;
    my $string = "";
    my @file_dims = ast_get_dimension_indexes($using_ast, "f");
    my @cols_dims = ast_get_dimension_indexes($using_ast, "c");
    my @line_dims = ast_get_dimension_indexes($using_ast, "l"); 
    my $total = @file_dims + @cols_dims + @line_dims; 

    my $i = 0; 

    foreach my $d (@file_dims){
	my $vr = $tuple->[$d]; 
	$string .= value_ref_get_pname($vr);
	$string .= '.'.value_ref_get_value($vr);
	if(++$i != $total){
	    $string .= '_';
	}
    }
    foreach my $d (@cols_dims){
	my $vr = $tuple->[$d]; 
	$string .= value_ref_get_pname($vr);
	$string .= '.'.value_ref_get_value($vr);
	if(++$i != $total){
	    $string .= '_';
	}
    }
    foreach my $d (@line_dims){
	my $vr = $tuple->[$d]; 
	$string .= value_ref_get_pname($vr);
	$string .= '.'.value_ref_get_value($vr);
	if(++$i != $total){
	    $string .= '_';
	}
    }
    return $string; 
}

sub save_program_output{
    die if @_ != 1; 
    my ($tuple) = @_;
    my $filename = "$output_dir/output/".tuple_to_output_filename($tuple).".out";
    system ("mv $tmp_out $filename");
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
	if(parameter_get_format_spec(value_ref_get_pname($vr)) 
	   eq $class_type){
	    push @class_spec, $vr; 
	}
	else{
	    push @class_spec, ["",""];
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
	my $pname = value_ref_get_pname($vr); 
	if(parameter_get_format_spec($pname) eq $format_spec){
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

    my $filename = $file_prefix.tuple_to_filename($file_class_tuples->[0]);
    my $fh; 
    if(not (open $fh, ">$filename")){
	warning_output("Cannot create result file '$filename': $! Using stdout."); 
	$fh = \*STDOUT; 
    }

    print_file_header($fh, "/bin/ls", $info_reported);
    print $fh '# ';
    
    # print first column header ie. parameter names of column parameters
    my @l_vr = get_value_refs_from_format_spec($file_class_tuples->[0], 'l');
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

sub startup{
    my @argv = @_; 
    init(); 
    parse_program_arguments(\@argv);
    #print ast_to_string($using_ast);
    check_ast($using_ast);
    #print ast_to_string($using_ast);
    populate_output_dir($output_dir);

# Creating the databases    
    my $time_db = new Result_Db($output_dir, "time");
    my $mem_db = new Result_Db($output_dir, "mem");
    my $usr_db; 
    if($post_exec_script_path){
	$usr_db = new Result_Db($output_dir, "usr");}

# Fetching the tuples and preparing the databses
    my @tuples = @{ast_get_tuples($using_ast)};
    foreach my $t (@tuples){
	$time_db->result_db_add_tuple($t);
	$mem_db->result_db_add_tuple($t);
	if($post_exec_script_path){
	    $usr_db->result_db_add_tuple($t);
	}
    }

# Print various info 
    print_info();
    create_readme_file(@argv);
    my $num_runs = 0; 
    foreach my $t (@tuples){
	my $cl = build_a_command_line($progtotest_command_template, $t);
	print "$cl\n";
	$num_runs++; 
    }
    if($timeout != -1){
	my $max_run_time = ($num_runs * $timeout) / 60;
	print "Maximum run time: $num_runs x $timeout = $max_run_time minutes. (".($max_run_time/60)." hours.)\n"; 
    }
    
# Everything seems to be OK. Starting experiments.
    print "\nEverything seems to be OK. Starting experiments.\n\n";
    
    foreach my $t (@tuples){
	my $cl = build_a_command_line($progtotest_command_template, $t);
	push @progtotest_command_lines, $cl;
	my ($time, $mem, $usr) =  run_child($cl);
	$time_db->result_db_set_result($t, $time);
	$mem_db->result_db_set_result($t, $mem);
	$usr_db->result_db_set_result($t, $usr) if($post_exec_script_path);
	
	# writing results... after each run for more safety. 
	write_result_files(\@tuples, $time_db,
			   $output_dir.'time/time_', "Wall clock time (in seconds)");
	write_result_files(\@tuples, $mem_db,
			   $output_dir.'mem/mem_', "Max memory usage (in MiB)");
	if($post_exec_script_path){
	    write_result_files(\@tuples, $usr_db,
			       $output_dir.'usr/usr_',
			       "User script output");
	}

	save_program_output($t); 
    }

# Finalize
    finalize_readme_file(); 

}

=head1 Runtime

Runtime - Program large scale time/memory mesurements through a command line interface. 


=head1 SYNOPSIS

 runtime -p PARAMETER_NAME parameter_value_1 .. parameter_value_n
 [-p PARAMETER2_NAME parameter2_value_1 .. parameter2_value_n]
 [-s post_output_script] [-m max_memory_usage (% total)] [ -t timeout value]
 -u using_expression -- command_line_template
 
=head1 DESCRIPTION 

    
Runtime can be used to program, run, and collect time or memory usage
statistics for a program with a large number of parameters, or for
multiple programs. 

Given a command line template, and a list of parameters with possible
values, Runtime does the following.

1. Create the command lines; 
2. run them, measuring time and memory usage; 
3. store the measurements results and store programs outputs in files
   properly named according to user specificatoin (See. Using expression.).
4. Write a README file containing data about the experiments so it can
   be easilly reproduced.

=head1 EXAMPLE 

Let's say we want to run the echo program multiple times with
different parameters.
We can do it with the following command line:

     runtime -p P1 a1 a2 -p P2 b1 b2 b3 -u P1cxP2l -- echo P1 P2

Which will:

- Run the following commands 

    echo a1 b1
    echo a1 b2
    echo a1 b3
    echo a2 b1
    echo a2 b2
    echo a2 b3

- Collect run times and memory usage and store them into file. 
One value per column for P1, one value per line for P2. 
(lowercase c stands for column, l for line, and f for file). 

- Store the results in files, lines and columns according to format
specifications in the using expression.  In our example P1cxP2l means
that time (and memory) results will be stored one value per column for
P1 and one value per line for P2.

This will lead to the following layout in the output file. 

    # P2    P1=a1   P1=a2
    b1      0.00    0.00
    b2      0.00    0.00
    b3      0.00    0.00

(time are 0.00 because executing "echo" is almost instantaneous.)

Result files are easy to plot using Gnuplot or other plotting tools.

=head1 PARAMETERS 

Each parameter is declared with the -p switch as follows. (Multiple parameters are declared with multiple -p switch.)

    -p PARAMETER_NAME value1 value2 value3 ...
    
PARAMETER_NAME is the parameter name in capital letter and is followed by all the parameters values (strings) separated by whitespaces.

Notice that this is also possible:
    
    -p NUM_THREADS `seq 1 32`
    
    
=head1 USING EXPRESSION

The using expression servs two purposes: 

1. It describes how to combine the parameters values to build the
command lines from the command line template.
2. It describes the format specification to write the results into
files lines and columns with an adequate format. 

The using expression is composed of parameters names, operators and format descriptors. 

- Parameters names are the names (in capital letters) of the
  parameters formerly declared.

- Operators are  'x' or '=' 

    'x' (carthesian product)  combines all the values from the left operand with the values from the right operands

for example ('l' and 'c' are format descriptors, you can safely ignore them for now.): 

runtime -p A a1 a2 -p B b1 b2 -u AlxBc -- echo A B C 
will program the execution of:
    echo a1 b1
    echo a1 b2
    echo a2 b1
    echo a2 b2

    '='   maps all the values of the right operand to a value of the left operand with respect to the input value order. 

for example:

    runtime -p A a1 a2 -p B b1 b2 -u Al=Bc -- echo A B C
    
will program the execution of:
    
    echo a1 b1
    echo a2 b2

You can combine them, and use paranthesis:
    
    runtime -p A a1 a2 -p B b1 b2 -p C c1 c2 -u "(Ac=Bl)xCf" -- echo A B C 

will program the execution of: 
    echo a1 b1 c1
    echo a1 b1 c2
    echo a2 b2 c1
    echo a2 b2 c2

Note that if you introduce paranthesis, you must quote the using
expression.

=head1 FORMAT SPECIFICATION

Format descriptor are associated with parameters to describe how the
mesurements will be stored in the results files. 
They can be either 'f', 'l', or 'c'. 
- f stands for "one value per file" 
- l stands for "one value per line"
- c stands for "one value per column"

So:
    runtime -p A a1 a2 -p B b1 b2 -p C c1 c2 -u AfxBcxCl -- echo A B C 
    
Will create two files in the time output directory named:
time_A.a1_B_C and time_A.a2_B_C

Each file contains times measurements laid out as follows:
    # C     B=b1    B=b2
    c1      0.00    0.00
    c2      0.00    0.00
    
i.e. One value per column for parameter B and one value per line for
parameter C.

=head1 OUTPUT DIRECTORY

Each execution of runtime creates a directory named after the current date. 
The directory contains
 - a time subdirectory,
 - a mem subdirectory, 
 - a README file
 - a usr directory when a user script is provided. 

Each subdirectory contains the reporting files except the output sub
directory which contains the output of every execution.

=head1 SEE ALSO

gnuplot
    
=head1 AUTHOR

Benjamin Negrevergne, E<lt>bnegreve@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010-2013 by Benjamin Negrevergne

This library is free software; you can redistribute it and/or modify
it under the terms of the GPLv3.

=cut

1;
__END__
