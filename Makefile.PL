# Copyright (C) 2010-2013, Benjamin Negrevergne.
use 5.012;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'Runtime',
    ABSTRACT          => 'lib/Runtime.pm',
    AUTHOR            => 'Benjamin Negrevergne <bnegreve@gmail.com>',
    VERSION_FROM      => 'lib/Runtime.pm',
    
    PREREQ_PM         => {'Parse::RecDescent'  => 1.967009,
			  'Proc::ProcessTable' => 0.45,
			  'Digest::MD5'        => 0.08 },
    EXE_FILES         => [ 'script/runtime' ],
    MAN1PODS          => { 'lib/runtime.pod' => '$(INST_MAN1DIR)/runtime.$(MAN1EXT)' },
    MAN3PODS          => { }
);
