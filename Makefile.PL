use 5.014002;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'Runtime',
    ABSTRACT          => 'lib/Runtime.pm',
    AUTHOR            => 'Benjamin Negrevergne <bnegreve@gmail.com>',
    VERSION_FROM      => 'lib/Runtime.pm',
    
    PREREQ_PM         => {'Parse::RecDescent' => 1.967009,
			  'Proc::ProcessTable' => 0.45},
    EXE_FILES         => [ 'script/runtime' ]
);
