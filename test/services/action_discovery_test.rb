# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Services
    class ActionDiscoveryTest < ActiveSupport::TestCase
      setup do
        @discovery = ActionDiscovery.new
      end

      test "discovers actions from filesystem" do
        actions = @discovery.call

        # Should find actions in test/dummy/captain_hook/*/actions/
        assert actions.size > 0, "Should discover at least one action from filesystem"

        # Check that we have the expected structure
        action = actions.first
        assert action.key?("provider")
        assert action.key?("event")
        assert action.key?("action")
        assert action.key?("async")
        assert action.key?("max_attempts")
        assert action.key?("priority")
        assert action.key?("retry_delays")
      end

      test "discovers stripe actions" do
        actions = @discovery.call
        stripe_actions = actions.select { |a| a["provider"] == "stripe" }

        assert stripe_actions.size > 0, "Should find Stripe actions"

        # Should find the PaymentIntentCreatedAction
        payment_intent_created = stripe_actions.find do |a|
          a["event"] == "payment_intent.created"
        end

        assert_not_nil payment_intent_created, "Should find payment_intent.created action"
        assert_equal "Stripe::PaymentIntentCreatedAction", payment_intent_created["action"]
        assert_equal 100, payment_intent_created["priority"]
        assert_equal true, payment_intent_created["async"]
        assert_equal 3, payment_intent_created["max_attempts"]
      end

      test "discovers square actions" do
        actions = @discovery.call
        square_actions = actions.select { |a| a["provider"] == "square" }

        assert square_actions.size > 0, "Should find Square actions"

        # Should find BankAccountAction with wildcard
        bank_account_action = square_actions.find do |a|
          a["event"] == "bank_account.*"
        end

        assert_not_nil bank_account_action, "Should find bank_account.* action"
        assert_equal "Square::BankAccountAction", bank_account_action["action"]
      end

      test "discovers webhook_site actions" do
        actions = @discovery.call
        webhook_site_actions = actions.select { |a| a["provider"] == "webhook_site" }

        assert webhook_site_actions.size > 0, "Should find webhook_site actions"

        test_action = webhook_site_actions.find { |a| a["event"] == "test" }
        assert_not_nil test_action, "Should find test action"
        assert_equal "WebhookSite::TestAction", test_action["action"]
      end

      test "for_provider filters actions by provider" do
        stripe_actions = ActionDiscovery.for_provider("stripe")

        assert stripe_actions.size > 0, "Should find actions for stripe"
        assert stripe_actions.all? { |a| a["provider"] == "stripe" }, "All actions should be for stripe"
      end

      test "for_provider returns empty array for unknown provider" do
        actions = ActionDiscovery.for_provider("nonexistent_provider")
        assert_equal [], actions
      end

      test "transforms class names correctly" do
        actions = @discovery.call

        # All class names should be in the format Provider::ClassName
        # Should NOT have CaptainHook:: prefix
        # Should NOT have ::Actions:: in the middle
        actions.each do |action|
          class_name = action["action"]

          assert_not class_name.start_with?("CaptainHook::"),
                     "Class name should not start with CaptainHook:: but got: #{class_name}"
          assert_not class_name.include?("::Actions::"),
                     "Class name should not contain ::Actions:: but got: #{class_name}"

          # Should have at least one :: (Provider::ClassName format)
          assert_operator class_name.count("::"), :>=, 1,
                          "Class name should have namespace separator but got: #{class_name}"
        end
      end

      test "handles actions with default values" do
        actions = @discovery.call

        # All actions should have retry_delays, even if not specified in details
        actions.each do |action|
          assert action["retry_delays"].is_a?(Array), "retry_delays should be an array"
          assert action["retry_delays"].size > 0, "retry_delays should not be empty"
        end
      end

      test "action classes have details method" do
        # Discover actions to ensure they're loaded
        actions = @discovery.call

        # Find a Stripe action from the discovered actions
        stripe_action = actions.find { |a| a["provider"] == "stripe" && a["event"] == "payment_intent.created" }
        assert_not_nil stripe_action, "Should find a Stripe action to test"

        # Get the class from the discovered action
        action_class_name = stripe_action["action"]
        action_class = action_class_name.constantize

        assert action_class.respond_to?(:details),
               "Action class should respond to .details"

        details = action_class.details
        assert details.key?(:event_type), "details should have :event_type"
        assert details.key?(:priority), "details should have :priority"
        assert details.key?(:async), "details should have :async"
        assert details.key?(:max_attempts), "details should have :max_attempts"
      end
    end
  end
end
