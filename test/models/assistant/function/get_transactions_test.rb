require "test_helper"

class Assistant::Function::GetTransactionsTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @fn = Assistant::Function::GetTransactions.new(@user)
  end

  test "includes transaction and entry ids so follow-up MCP writes can target rows precisely" do
    result = @fn.call("page" => 1, "order" => "desc")
    transaction = result[:transactions].first

    assert transaction[:transaction_id].present?
    assert transaction[:entry_id].present?
  end
end
