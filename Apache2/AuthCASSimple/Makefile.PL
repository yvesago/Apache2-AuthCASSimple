use inc::Module::Install;

name            'Apache2-AuthCASSimple';
all_from        'lib/Apache2/AuthCASSimple.pm';

requires 'Apache2::Const';
requires 'Apache2::RequestUtil';
requires 'Apache2::RequestRec';
requires 'Apache2::Log';
requires 'Apache2::Connection';
requires 'Apache::Session::Wrapper';
requires 'Authen::CAS::Client';

auto_install;
WriteAll;

