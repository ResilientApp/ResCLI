#!/usr/bin/env ruby
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'optparse'
require 'open3'
require 'inifile'
require 'io/console'
require 'pty'
require 'httpx'
require 'json'
require 'bcrypt'

module ResCli
  class AuthService

    def self.backend_login(username, password)
      url = 'https://server.resilientdb.com/getUser'
      encrypted_password = BCrypt::Password.create(password)
      
      payload = { email: username, password: password }
      
      response = HTTPX.post(url, json: payload)
      
      case response.status
      when 200
        body = response.to_s
        json_response = JSON.parse(body)
        if json_response['success'] == true
          return true
        else
          return false
        end
      when 500
        return false # Server error
      else
        return false # Other HTTP errors
      end
    rescue HTTPX::Error => e
      false
    end

    def self.login
      print "Enter your username: "
      username = gets.chomp

      print "Enter your password: "
      password = STDIN.noecho(&:gets).chomp
      puts 

      if backend_login(username, password)
        ResCli::CLI.set_logged_in_user(username)
        puts "Login successful. Welcome, #{username}!"
      else
        puts "Login failed. Invalid username or password."
      end
    end

    def self.logout
      ResCli::CLI.set_logged_in_user(nil)
      puts "Logout successful. Goodbye!"
    end

    def self.backend_sign_up(email, password)
      url = 'https://server.resilientdb.com/setUser'

      encrypted_password = BCrypt::Password.create(password)

      payload = { email: email, password: encrypted_password }
  
      response = HTTPX.post(url, json: payload)
  
      if response.status == 200
        return { success: true, message: "Sign up successful. Welcome, #{email}!" }
      elsif response.status == 409
        return { success: false, message: "Sign up failed. User with email #{email} already exists." }
      else
        return { success: false, message: "Sign up failed. Error registering user with email #{email}." }
      end
    rescue HTTPX::Error => e
      { success: false, message: "Sign up failed. #{e.message}" }
    end
  
    def self.sign_up
      print "Enter your email: "
      email = gets.chomp
  
      print "Enter your password: "
      password = STDIN.noecho(&:gets).chomp
      puts
  
      result = backend_sign_up(email, password)
  
      if result[:success]
        ResCli::CLI.set_logged_in_user(email)
        puts result[:message]
      else
        puts result[:message]
      end
    end

    # def self.github_login
    #   print "Enter your GitHub username: "
    #   github_username = gets.chomp

    #   print "Enter your GitHub token (you can use a personal access token): "
    #   github_token = STDIN.noecho(&:gets).chomp
    #   puts 

    #   if github_authentication(github_username, github_token)
    #     ResCli::CLI.set_logged_in_user(github_username)
    #     puts "GitHub login successful. Welcome, #{github_username}!"
    #   else
    #     puts "GitHub login failed. Invalid username or token."
    #   end
    # end

    private

    # def self.github_authentication(username, token)
    #   return !username.empty? && !token.empty?
    # end
  end

  class CLI

    CONFIG_FILE_PATH = 'config.ini'
    @@config = IniFile.load(CONFIG_FILE_PATH)

    def self.start
      options = {}
      OptionParser.new do |opts|
        opts.banner = "Usage: #{$PROGRAM_NAME} [options]"
    
        opts.on('-c', '--create TYPE', [:resdb, :sdk], 'Create a new ResDB or PythonSDK instance') do |type|
          create_instance(type)
        end

        opts.on('-e', '--exec-into INSTANCE_ID', 'Bash into a running ResDB or PythonSDK instance') do |instance_id|
          exec_into(instance_id)
        end

        opts.on('-v', '--view-instances', 'View details about running instances') do
          view_instances
        end

        opts.on('-d', '--delete INSTANCE_ID', 'Delete a running ResDB or PythonSDK instance') do |instance_id|
          delete_instance(instance_id)
        end

        opts.on('-t', '--test-api', 'Test API') do
          testAPI
        end

        opts.on('-h', '--help', 'Display this help message') do
          help
          exit
        end

        opts.on('--login', 'Login with username and password') do
          AuthService.login
        end

        opts.on('--sign-up', 'Sign up with email and password') do
          AuthService.sign_up
        end

        # opts.on('-gl', '--github-login', 'Login with GitHub') do
        #   AuthService.github_login
        # end

        opts.on('--whoami', 'Display the current logged-in user') do
          CLI.whoami
        end
    
        opts.on('--logout', 'Logout') do
          AuthService.logout
        end
      end.parse!
    end    

    def self.get_logged_in_user
      @@config['User']['Current_User'].split('@').first
    end

    def self.whoami
      logged_in_user = get_logged_in_user
      puts "Current logged-in user: #{logged_in_user}"
    end    

    def self.set_logged_in_user(username)
        @@config['User']['Current_User'] = username
        @@config.write    
    end

    def self.create_instance(type)
        begin
            # Implement create instance logic
            puts "Creating #{type} instance..."
        
            # Run Docker command to create a new instance

            loggedin_user = get_logged_in_user
            container_name = "#{loggedin_user}-#{type}_instance"

            command = ["docker", "run", "--name", container_name, "-d", "expolab/#{type}:arm64"]
        
            output, status = Open3.capture2(*command)
        
            unless status.success?
                raise "Error creating instance: #{output}"
            end
        
            puts "#{type} instance created successfully with container name: #{container_name}"
        
            rescue => error
            $stderr.puts "Error creating instance: #{error}"
            end
    end

    def self.exec_into(instance_id)
      begin
        command = ["docker", "exec", "-it", instance_id, "bash"]
        pid = Process.spawn(*command, in: STDIN, out: STDOUT, err: STDERR, unsetenv_others: true)
        Process.wait(pid)
      rescue => error
        $stderr.puts "Error executing command: #{error}"
      end
    end    

    def self.view_instances
        begin
            docker_command = ["docker", "container", "ls", "--format", "table {{.ID}}\t{{.Image}}\t{{.Names}}"]
            output, status = Open3.capture2(*docker_command)
        
            unless status.success?
              raise "Error running docker command: #{output}"
            end
        
            puts output
        
          rescue => error
            $stderr.puts "An unexpected error occurred: #{error}"
          end
    end

    def self.delete_instance(instance_id)
        begin
            # Implement delete instance logic
            puts "Deleting instance #{instance_id}..."
        
            # Stop the Docker container
            _, stop_status = Open3.capture2("docker stop #{instance_id}")
        
            unless stop_status.success?
              raise "Error stopping instance: #{stop_status}"
            end
        
            # Remove the Docker container
            _, rm_status = Open3.capture2("docker rm #{instance_id}")
        
            unless rm_status.success?
              raise "Error removing instance: #{rm_status}"
            end
        
            puts "Instance deleted successfully."
        
          rescue => error
            $stderr.puts "Error deleting instance: #{error}"
          end
    end

    def self.testAPI()
      begin
        puts "Testing API..."
    
        response = HTTPX.get("https://server.resilientdb.com/test")
        
        if response.status == 200
          puts response.body
        else
          puts "Error: #{response.status}"
        end
        
      rescue HTTPX::Error => e
        puts "HTTPX Error: #{e.message}"
      rescue StandardError => e
        puts "Error: #{e.message}"
      end
    end

    def self.help
        puts "Usage: #{$PROGRAM_NAME} [options]"
        puts "\nOptions:"
        puts "  -li, --login                    Login with username and password"
        puts "  -su, --sign-up                  Sign up with email and password"
        # puts "  -gl, --github-login             Login with GitHub"
        puts "  -lo, --logout                   Logout"
        puts "  -c,  --create TYPE              Create a new ResDB or PythonSDK instance"
        puts "  -e,  --exec-into INSTANCE_ID    Bash into a running ResDB or PythonSDK instance"
        puts "  -v,  --view-instances           View details about running instances"
        puts "  -d,  --delete INSTANCE_ID       Delete a running ResDB or PythonSDK instance"
        puts "  -w,  --whoami                   Display the current logged-in user"        
        puts "  -h,  --help                     Display this help message"
    end
  end
end

# Entry point
ResCli::CLI.start