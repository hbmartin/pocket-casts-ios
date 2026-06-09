credentials_script_tests:
	# ruleid: makefile.no-hardcoded-system-ruby
	/usr/bin/ruby scripts/tests/generate_credentials_test.rb

credentials_script_tests_safe:
	# ok: makefile.no-hardcoded-system-ruby
	ruby scripts/tests/generate_credentials_test.rb
