use inc::Module::Install;

name            'Apache2-AuthCASSimple';
all_from        'lib/Apache2/AuthCASSimple.pm';

requires 'mod_perl2' => 2.0;
requires 'Apache::Session::Wrapper';
requires 'Authen::CAS::Client';

build_requires  'Pod::Coverage';

auto_install;

install_script('scripts/delete_session_data.pl');

tests('t/*.t');

WriteAll;

