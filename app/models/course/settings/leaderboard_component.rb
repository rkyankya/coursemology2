# frozen_string_literal: true
class Course::Settings::LeaderboardComponent < Course::Settings::Component
  include ActiveModel::Conversion

  validates :display_user_count, numericality: { greater_than_or_equal_to: 0 }

  # Returns the title of leaderboard component
  #
  # @return [String] The custom or default title of leaderboard component
  def title
    settings.title
  end

  # Sets the title of leaderboard component
  #
  # @param [String] title The new title
  def title=(title)
    title = nil if title.blank?
    settings.title = title
  end

  # Returns the number of users to be displayed on the leaderboard
  #
  # @return [Integer] The number of users to be displayed
  def display_user_count
    settings.display_user_count || 30
  end

  # Set the number of users to be displayed on the leaderboard
  #
  # @param [Integer] count The number of users to be displayed
  def display_user_count=(count)
    settings.display_user_count = count
  end

  # Returns whether group leaderboard is enabled (disabled by default).
  #
  # @return [Boolean] Setting on whether group leaderboard is enabled.
  def enable_group_leaderboard
    group_leaderboard_settings.enabled == true
  end

  # Enable or disable the option to display group leaderboard
  #
  # @param [Boolean|Integer|String] option Setting on whether group leaderboard is enabled.
  #   By default, simple_form provides '0' and '1' for boolean fields.
  #   This method will handle this conversion to Boolean.
  def enable_group_leaderboard=(option)
    option = ActiveRecord::Type::Boolean.new.cast(option)
    group_leaderboard_settings.enabled = option
  end

  # Returns the title of group leaderboard
  #
  # @return [String] The custom or default title of group leaderboard component
  def group_leaderboard_title
    group_leaderboard_settings.title
  end

  # Sets the title of group leaderboard
  #
  # @param [String] title The new title
  def group_leaderboard_title=(group_leaderboard_title)
    group_leaderboard_title = nil if group_leaderboard_title.blank?
    group_leaderboard_settings.title = group_leaderboard_title
  end

  private

  def group_leaderboard_settings
    @group_leaderboard_settings ||= settings.settings(:group_leaderboard)
  end
end
