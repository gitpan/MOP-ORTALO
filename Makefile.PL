use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	      'NAME'	=> 'MOP',
	      'VERSION_FROM' => 'MOP/MOP.pm', # finds $VERSION
	      'dist'    => { COMPRESS=>'gzip --best', SUFFIX=>'gz'},
	      );
