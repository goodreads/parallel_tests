require 'parallel_tests'
require 'parallel_tests/test/runner'

module ParallelTests
  module Test
    class RuntimeLogger
      @@has_started = false

      @@class_to_test_file_map = {}
      output = `egrep -r -E "class .*? < .*?::.*?Test" test|grep -v "#" | sed s'/\:[ ]*/\:/g'|sed 's/class //g'|sed 's/ <.*//g'|sed 's/rb:/rb /g'|awk {'print $2,$1'}`
      output.each_line do |line|
        klass,file = line.chomp.split(/ /)
        @@class_to_test_file_map[klass] = file
      end

      class << self
        def log(test, start_time, end_time)
          if !@@has_started # make empty log file
            File.open(logfile, 'w'){}
            @@has_started = true
          end

          locked_appending_to(logfile) do |file|
            # we sometimes here back from these classes - this must be setup or
            # teardown stuff (i think -e comes from the cli invocation of test
            # runner). anyway, we don't want to log any of this to our results
            # file
            unless ['-e', 'ActionDispatch::IntegrationTest',
                    'ActiveSupport::TestCase', 'ActionController::TestCase'
                    ].include?(test.to_s)
              file.puts(message(test, start_time, end_time))
            end
          end
        end

        private

        def message(test, start_time, end_time)
          delta = "%.2f" % (end_time.to_f-start_time.to_f)
          filename = @@class_to_test_file_map[test.to_s]
          "#{filename}:#{delta}"
        end

        # Note: this is a best guess at conventional test directory structure, and may need
        # tweaking / post-processing to match correctly for any given project
        def class_directory(suspect)
          result = "test/"

          if defined?(Rails)
            result += case suspect.superclass.name
            when "ActionDispatch::IntegrationTest"
              "integration/"
            when "ActionDispatch::PerformanceTest"
              "performance/"
            when "ActionController::TestCase"
              "functional/"
            when "ActionView::TestCase"
              "unit/helpers/"
            else
              "unit/"
            end
          end
          result
        end

        # based on https://github.com/grosser/single_test/blob/master/lib/single_test.rb#L117
        def class_to_filename(suspect)
          word = suspect.to_s.dup
          return word unless word.match /^[A-Z]/ and not word.match %r{/[a-z]}

          word.gsub!(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          word.gsub!(/([a-z\d])([A-Z])/, '\1_\2')
          word.gsub!(/\:\:/, '/')
          word.tr!("-", "_")
          word.downcase!
          word
        end

        def locked_appending_to(file)
          File.open(file, 'a') do |f|
            begin
              f.flock File::LOCK_EX
              yield f
            ensure
              f.flock File::LOCK_UN
            end
          end
        end

        def logfile
          ParallelTests::Test::Runner.runtime_log
        end
      end
    end
  end
end

require 'test/unit/testsuite'
class ::Test::Unit::TestSuite
  alias :run_without_timing :run unless defined? @@timing_installed

  def run(result, &progress_block)
    start_time = ParallelTests.now
    run_without_timing(result, &progress_block)
    end_time = ParallelTests.now
    ParallelTests::Test::RuntimeLogger.log(self, start_time, end_time)
  end

  @@timing_installed = true
end
