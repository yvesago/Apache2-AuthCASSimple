use inc::Module::Install;

name            'Apache2-AuthCASSimple';
perl_version    '5.008';
all_from        'lib/Apache2/AuthCASSimple.pm';
version_from        'lib/Apache2/AuthCASSimple.pm';

requires 'mod_perl' => 1.99;
requires 'Apache::Session::Wrapper';
requires 'Authen::CAS::Client';
requires 'Apache2::Log';
requires 'Apache2::Connection';
requires 'CGI';

build_requires  'Pod::Coverage';
build_requires  'Test::More';
build_requires 'mod_perl2' => 1.99;
build_requires 'Apache::Session::Wrapper';
build_requires 'Authen::CAS::Client';
build_requires 'Apache2::Log';
build_requires 'Apache2::Connection';
build_requires 'CGI';

auto_install;

no_index directory => 'examples';
#install_script('scripts/delete_session_data.pl');

tests('t/*.t');

WriteAll;

