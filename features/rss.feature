Feature: Wiki
  In order to share rss data
  A user
  Should be able to see rss changes


  Scenario: check if RSS feeds from page menu works properly
    When I go to the main page
    And I login as "johno"
    And I create "/" page with title "Root page"
    And I follow "RSS feed of page changes"
    Then I should see "Root page changes"

  Scenario: check if RSS feed of page changes from page menu works properly without login
      When I go to the main page
      And I login as "johno"
      And I create "/" page with title "Root page"
      And I follow "RSS feed of page changes"
      Then I should see "Root page changes"
      When I go to the main page
      And I follow "Log out"
      And I follow "RSS feed of page changes"
      Then I should see "Root page changes"

  Scenario: check if RSS works properly
    When I go to the main page
    And I login as "johno"
    And I create "/" page with title "Root page"
    And I follow "RSS feed of page changes"
    Then I should see "Root page changes"
    When I go to the main page
    And I edit "/" page with title "Some NEW title"
    And I follow "RSS feed of page changes"
    Then I should see "Some NEW title changes"

  Scenario: check if user who has not permission can not see RSS
    Given user "johno" exists
    Given user "matell" exists
    When I go to the main page
    And I login as "matell"
    And I create "/" page
    And I follow "RSS feed of page changes"
    Then I should see "Some title changes"
    When I go to the main page
    And page "/" is viewable by "matell"
    And I logout
    And I login as "johno"
    And I should not see "RSS feed of page changes"
    When I go to /?rss
    Then I should not see "Some title changes"

  Scenario: check if RSS feed of page changes from page menu works properly without login
    When I go to the main page
    And I login as "johno"
    And I fill in "title" with "Root page"
    And I fill in "body" with "Root body!"
    And I fill in "summary" with "A change"
    And I select "PeWe Layout" from "layout"
    And I press "Create"
    And I follow "Log out"
    And I follow "RSS feed of page changes"
    Then I should see "Root page changes"
    

 Scenario: check if privatec page is not viewable for all users
   Given user "johno" exists
   When I go to the main page
   And I login as "johno"
   And I create "/" page
   And page "/" is viewable by "johno"
   And I follow "RSS feed of page changes"
   Then I should see "Some title changes"
   And I go to the main page
   And I logout
   Then I should not see "RSS feed of page changes"

 Scenario: check diif link in rss
   When I go to the main page
   And I login as "johno"
   And I fill in "title" with "Root page"
   And I fill in "body" with "Root body!"
   And I fill in "summary" with "A change"
   And I select "PeWe Layout" from "layout"
   And I press "Create"
   And I follow "RSS feed of page changes"
   Then I should see "Root page changes"
   When I go to the main page
   And I follow "Edit"
   And I fill in "parts_body" with "Some NEW haluzina"
   And I press "Save"
   Then I should see "Page successfully updated."
   When I follow "RSS feed of page changes"
   Then I should see "johno (johno) edited body"
    