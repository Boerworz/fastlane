require 'snapshot/simulator_launchers/simulator_launcher_base'

module Snapshot
  class SimulatorLauncher < SimulatorLauncherBase
    def default_number_of_simultaneous_simulators
      cpu_count = OS.cpu_count
      if cpu_count <= 2
        return OS.cpu_count
      end

      return OS.cpu_count - 1
    end

    def take_screenshots_simultaneously
      languages_finished = {}
      launcher_config.launch_args_set.each do |launch_args|
        launcher_config.languages.each_with_index do |language, language_index|
          locale = nil
          if language.kind_of?(Array)
            locale = language[1]
            language = language[0]
          end
          # Break up the array of devices into chunks that can
          # be run simultaneously.
          launcher_config.devices.each_slice(default_number_of_simultaneous_simulators) do |devices|
            languages_finished[language] = launch_simultaneously(devices, language, locale, launch_args)
          end
        end
      end
      launcher_config.devices.each_with_object({}) do |device, results_hash|
        results_hash[device] = languages_finished
      end
    end

    def launch_simultaneously(devices, language, locale, launch_arguments)
      prepare_for_launch(language, locale, launch_arguments)

      add_media(device_types(:photo, launcher_config.add_photos)) if launcher_config.add_photos
      add_media(device_types(:video, launcher_config.add_videos)) if launcher_config.add_videos

      command = TestCommandGenerator.generate(devices: devices, language: language, locale: locale)

      prefix_hash = [
        {
          prefix: "Running Tests: ",
          block: proc do |value|
            value.include?("Touching")
          end
        }
      ]

      FastlaneCore::CommandExecutor.execute(command: command,
                                          print_all: true,
                                      print_command: true,
                                             prefix: prefix_hash,
                                            loading: "Loading...",
                                              error: proc do |output, return_code|
                                                ErrorHandler.handle_test_error(output, return_code)

                                                # no exception raised... that means we need to retry
                                                UI.error "Caught error... #{return_code}"

                                                self.current_number_of_retries_due_to_failing_simulator += 1
                                                if self.current_number_of_retries_due_to_failing_simulator < 20
                                                  launch_simultaneously(language, locale, launch_arguments)
                                                else
                                                  # It's important to raise an error, as we don't want to collect the screenshots
                                                  UI.crash!("Too many errors... no more retries...")
                                                end
                                              end)
      raw_output = File.read(TestCommandGenerator.xcodebuild_log_path(language: language, locale: locale))

      dir_name = locale || language

      return Collector.fetch_screenshots(raw_output, dir_name, '', launch_arguments.first)
    end
  end
end
