use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'MOP::Remote',
    'VERSION_FROM' => 'Remote.pm', # finds $VERSION
);
