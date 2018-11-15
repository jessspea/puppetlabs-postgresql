require 'spec_helper_acceptance'

describe 'postgresql::server::db', unless: UNSUPPORTED_PLATFORMS.include?(os[:family]) do
  # rubocop:disable Metrics/LineLength
  it 'creates a database' do
    begin
# need to create tmp folder on remote system
      tmpdir = run_shell('mktemp').first['result']['stdout']
      pp = <<-MANIFEST
        class { 'postgresql::server':
          postgres_password => 'space password',
        }
        postgresql::server::tablespace { 'postgresql-test-db':
          location => '#{tmpdir}',
        } ->
        postgresql::server::db { 'postgresql-test-db':
          comment    => 'testcomment',
          user       => 'test-user',
          password   => 'test1',
          tablespace => 'postgresql-test-db',
        }
      MANIFEST

      apply_manifest(pp, catch_failures: true)
      apply_manifest(pp, catch_changes: true)

      # Verify that the postgres password works
      run_shell("echo 'localhost:*:*:postgres:\'space password\'' > /root/.pgpass")
      run_shell('chmod 600 /root/.pgpass')
      run_shell("psql -U postgres -h localhost --command='\\l'")

      psql('--command="select datname from pg_database" "postgresql-test-db"') do |r|
        expect(r.stdout).to match(%r{postgresql-test-db})
        expect(r.stderr).to eq('')
      end

      psql('--command="SELECT 1 FROM pg_roles WHERE rolname=\'test-user\'"') do |r|
        expect(r.stdout).to match(%r{\(1 row\)})
      end

      result = run_shell('psql --version')
      version = result.first['result']['stdout'].match(%r{\s(\d{1,2}\.\d)})[1]
      comment_information_function = if version.to_f > 8.1
                                       'shobj_description'
                                     else
                                       'obj_description'
                                     end
      psql("--dbname postgresql-test-db --command=\"SELECT pg_catalog.#{comment_information_function}(d.oid, 'pg_database') FROM pg_catalog.pg_database d WHERE datname = 'postgresql-test-db' AND pg_catalog.#{comment_information_function}(d.oid, 'pg_database') = 'testcomment'\"") do |r|
        expect(r.stdout).to match(%r{\(1 row\)})
      end
    ensure
      psql('--command=\'drop database "postgresql-test-db" postgres\'')
      psql('--command="DROP USER test"')
    end
  end
end
