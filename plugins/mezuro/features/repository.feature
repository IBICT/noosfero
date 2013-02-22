Feature: Repository
  As a Mezuro user
  I want to create, edit, remove and process a repository

  Background:
    Given the following users
      | login     | name       |
      | joaosilva | Joao Silva |
    And I am logged in as "joaosilva"
    And "Mezuro" plugin is enabled
    And the following community
      | identifier  | name         |
      | mycommunity | My Community |
    And "Joao Silva" is admin of "My Community"
    And I have a Mezuro project with the following data
      | name        | Sample Project      |
      | description | Sample Description  |
      | community   | mycommunity         |
    And I have a Mezuro configuration with the following data
      | name        | Sample Configuration|
      | description | Sample Description  |
      | user        | joaosilva           |
    And I am on article "Sample Project"    
    And I should be on /mycommunity/sample-project
    
  Scenario: I want to see the Mezuro repository input form
    When I follow "Add Repository"
    Then I should see "Name"
    And I should see "Description"
    And I should see "License"
    And I should see "Process Period"
    And I should see "Type"
    And I should see "Address"
    And I should see "Configuration"
    And I should see "Add" button

  Scenario: I want to add a repository with no name
    Given I follow "Add Repository"
    When I fill the fields with the new following data
      | repository_name               |                                                                 |
      | repository_description        | My Description                                                  |
      | repository_license            | ISC License (ISC)                                               |
      | repository_process_period     | Not Periodically                                                |
      | repository_type               | SUBVERSION                                                      |
      | repository_address            | https://qt-calculator.svn.sourceforge.net/svnroot/qt-calculator |
      | repository_configuration_id   | Sample Configuration                                            |
    And I press "Add"
    Then I should see "Please fill all fields marked with (*)." inside an alert
  
  Scenario: I want to add a repository with no address
    Given I follow "Add Repository"
    When I fill the fields with the new following data
      | repository_name               | My Name                                                         |
      | repository_description        | My Description                                                  |
      | repository_license            | ISC License (ISC)                                               |
      | repository_process_period     | Not Periodically                                                |
      | repository_type               | SUBVERSION                                                      |
      | repository_address            |                                                                 |
      | repository_configuration_id   | Sample Configuration                                            |
    And I press "Add"
    Then I should see "Please fill all fields marked with (*)." inside an alert

  Scenario: I want to add a repository with a invalid address for git repository
    Given I follow "Add Repository"
    When I fill the fields with the new following data
      | repository_name               | My Name                                                         |
      | repository_description        | My Description                                                  |
      | repository_license            | ISC License (ISC)                                               |
      | repository_process_period     | Not Periodically                                                |
      | repository_type               | GIT                                                             |
      | repository_address            | https://invalid-address.any-extension                           |
      | repository_configuration_id   | Sample Configuration                                            |
    And I press "Add"
    Then I should see "Address does not match type GIT chosen." inside an alert

  #Scenario: I want to add a repository with valid attributes
        
