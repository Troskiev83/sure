require "test_helper"

class Assistant::Function::CategorizeTransactionsTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @account = accounts(:depository)
    @category = categories(:food_and_drink)
    @entry = @account.entries.create!(
      name: "Uncategorized coffee",
      date: Date.current,
      amount: 12.34,
      currency: "USD",
      entryable: Transaction.new
    )
    @transaction = @entry.transaction
    @fn = Assistant::Function::CategorizeTransactions.new(@user)
  end

  test "to_definition returns valid JSON shape" do
    definition = @fn.to_definition

    assert_equal "categorize_transactions", definition[:name]
    assert_kind_of String, definition[:description]
    assert_equal "object", definition[:params_schema][:type]
    assert_includes definition[:params_schema][:required], "changes"
  end

  test "dry run previews changes without writing" do
    result = @fn.call(
      "changes" => [
        {
          "transaction_id" => @transaction.id,
          "category_name" => @category.name,
          "expected_date" => @entry.date.iso8601,
          "expected_amount" => @entry.amount.to_s,
          "expected_account" => @account.name,
          "expected_current_category" => "Uncategorized"
        }
      ]
    )

    assert_equal true, result[:success]
    assert_equal true, result[:dry_run]
    assert_equal 1, result[:changes].size
    assert_equal "would_update", result[:changes].first[:status]
    assert_nil @transaction.reload.category
    assert_not @entry.reload.user_modified?
  end

  test "write requires user confirmation" do
    result = @fn.call(
      "dry_run" => false,
      "changes" => [
        {
          "transaction_id" => @transaction.id,
          "category_name" => @category.name
        }
      ]
    )

    assert_equal false, result[:success]
    assert_equal "confirmation_required", result[:error]
    assert_nil @transaction.reload.category
  end

  test "confirmed write categorizes transaction and protects manual edit" do
    result = @fn.call(
      "dry_run" => false,
      "confirmed_by_user" => true,
      "changes" => [
        {
          "transaction_id" => @transaction.id,
          "category_name" => @category.name,
          "expected_date" => @entry.date.iso8601,
          "expected_amount" => @entry.amount.to_s,
          "expected_account" => @account.name,
          "expected_current_category" => "Uncategorized"
        }
      ]
    )

    assert_equal true, result[:success]
    assert_equal false, result[:dry_run]
    assert_equal "updated", result[:changes].first[:status]
    assert_equal @category, @transaction.reload.category
    assert @transaction.locked?(:category_id)
    assert @entry.reload.user_modified?
  end

  test "does not categorize transactions outside user's family" do
    other_family = Family.create!(name: "Other", currency: "USD", locale: "en", country: "US", timezone: "UTC")
    other_account = other_family.accounts.create!(name: "Other Checking", balance: 0, currency: "USD", accountable: Depository.new)
    other_entry = other_account.entries.create!(
      name: "Other transaction",
      date: Date.current,
      amount: 20,
      currency: "USD",
      entryable: Transaction.new
    )

    result = @fn.call(
      "dry_run" => false,
      "confirmed_by_user" => true,
      "changes" => [
        {
          "transaction_id" => other_entry.transaction.id,
          "category_name" => @category.name
        }
      ]
    )

    assert_equal true, result[:success]
    assert_equal "not_found", result[:changes].first[:status]
    assert_nil other_entry.transaction.reload.category
  end

  test "blocks transfer categorization unless explicitly allowed" do
    @transaction.update!(kind: "funds_movement")

    result = @fn.call(
      "dry_run" => false,
      "confirmed_by_user" => true,
      "changes" => [
        {
          "transaction_id" => @transaction.id,
          "category_name" => @category.name
        }
      ]
    )

    assert_equal true, result[:success]
    assert_equal "blocked_transfer", result[:changes].first[:status]
    assert_nil @transaction.reload.category
  end
end
