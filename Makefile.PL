use 5.014002;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Runtime',
    VERSION_FROM      => 'lib/Runtime.pm', # finds $VERSION
    PREREQ_PM         => {'Parse::RecDescent' => 1.967009, 'Proc::ProcessTable' => 0.45}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Runtime.pm', # retrieve abstract from module
       AUTHOR         => 'Benjamin Negrevergne <bnegreve@gmail.com>') : ()),
);
