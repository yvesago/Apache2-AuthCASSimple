use inc::Module::Install;

name            'Apache2-AuthCASSimple';
all_from        'lib/Apache2/AuthCASSimple.pm';

requires 'mod_perl2' => 1.99;
requires 'Apache::Session::Wrapper';
requires 'Authen::CAS::Client';

build_requires  'Pod::Coverage';
build_requires 'mod_perl2' => 1.99;
build_requires 'Apache::Session::Wrapper';
build_requires 'Authen::CAS::Client';

auto_install;

#install_script('scripts/delete_session_data.pl');

tests('t/*.t');

WriteAll;

