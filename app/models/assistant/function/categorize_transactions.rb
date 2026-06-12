class Assistant::Function::CategorizeTransactions < Assistant::Function
  class << self
    def name
      "categorize_transactions"
    end

    def description
      <<~INSTRUCTIONS
        Use this to preview or apply category changes to a user's transactions.

        Always call this with dry_run omitted or true first. Only set dry_run to false after the user explicitly confirms the proposed category changes. Use transaction_id or entry_id values returned by get_transactions so the write targets exact rows.

        Safety behavior:
        - dry_run defaults to true and never writes
        - writes require confirmed_by_user: true
        - transactions are scoped to the current user's family
        - transfers are skipped unless allow_transfer is true for that change
        - expected_* fields are optional stale-row guards and should be supplied when available
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "changes" ],
      properties: {
        dry_run: {
          type: "boolean",
          description: "Defaults to true. When true, returns the changes that would be applied without writing."
        },
        confirmed_by_user: {
          type: "boolean",
          description: "Required to be true when dry_run is false."
        },
        changes: {
          type: "array",
          description: "Category changes to preview or apply.",
          minItems: 1,
          items: {
            type: "object",
            required: [ "category_name" ],
            additionalProperties: false,
            properties: {
              transaction_id: {
                type: "string",
                description: "Transaction id returned by get_transactions."
              },
              entry_id: {
                type: "string",
                description: "Entry id returned by get_transactions. Used when transaction_id is not supplied."
              },
              category_name: {
                enum: family_category_names,
                description: "Target category name. Use Uncategorized to clear the category."
              },
              expected_date: {
                type: "string",
                description: "Optional stale-row guard in YYYY-MM-DD format."
              },
              expected_amount: {
                type: "string",
                description: "Optional stale-row guard. Compared by absolute amount."
              },
              expected_account: {
                type: "string",
                description: "Optional stale-row guard for the account name."
              },
              expected_current_category: {
                type: "string",
                description: "Optional stale-row guard for the current category name, or Uncategorized."
              },
              allow_transfer: {
                type: "boolean",
                description: "Set true only when the user explicitly wants to categorize a transfer."
              }
            }
          }
        }
      }
    )
  end

  def call(params = {})
    params = params.to_h.with_indifferent_access
    changes = Array(params[:changes])
    dry_run = params.key?(:dry_run) ? boolean_type.cast(params[:dry_run]) : true
    confirmed_by_user = boolean_type.cast(params[:confirmed_by_user])

    return failure("changes_required", "At least one change is required.") if changes.empty?
    return failure("confirmation_required", "confirmed_by_user must be true when dry_run is false.") if !dry_run && !confirmed_by_user

    results = changes.each_with_index.map do |change, index|
      process_change(change.to_h.with_indifferent_access, index: index, dry_run: dry_run)
    end

    {
      success: true,
      dry_run: dry_run,
      applied_count: results.count { |result| result[:status] == "updated" },
      skipped_count: results.count { |result| result[:status] != "updated" },
      changes: results
    }
  end

  private
    def process_change(change, index:, dry_run:)
      transaction = find_transaction(change)
      return base_result(change, index).merge(status: "not_found") unless transaction

      result = transaction_result(transaction, index)
      expected_mismatches = expectation_mismatches(transaction, change)
      return result.merge(status: "expectation_mismatch", mismatches: expected_mismatches) if expected_mismatches.any?

      return result.merge(status: "blocked_transfer") if transaction.transfer? && !boolean_type.cast(change[:allow_transfer])

      category = find_category(change[:category_name])
      return result.merge(status: "category_not_found", requested_category: change[:category_name]) unless category || uncategorized?(change[:category_name])

      result = result.merge(target_category: category&.name)
      return result.merge(status: "would_update") if dry_run

      apply_category!(transaction, category)
      result.merge(status: "updated")
    end

    def find_transaction(change)
      if change[:transaction_id].present?
        transaction_scope.find_by(id: change[:transaction_id])
      elsif change[:entry_id].present?
        entry = entry_scope.find_by(id: change[:entry_id], entryable_type: "Transaction")
        transaction_scope.find_by(id: entry.entryable_id) if entry
      end
    end

    def transaction_scope
      @transaction_scope ||= Transaction.family_scope(family).includes(:category, entry: :account)
    end

    def entry_scope
      @entry_scope ||= Entry.family_scope(family)
    end

    def expectation_mismatches(transaction, change)
      entry = transaction.entry
      mismatches = []

      if change[:expected_date].present? && change[:expected_date] != entry.date.iso8601
        mismatches << { field: "date", expected: change[:expected_date], actual: entry.date.iso8601 }
      end

      if change[:expected_amount].present? && parse_amount(change[:expected_amount]) != entry.amount.abs
        mismatches << { field: "amount", expected: change[:expected_amount], actual: entry.amount.abs.to_s }
      end

      if change[:expected_account].present? && change[:expected_account] != entry.account.name
        mismatches << { field: "account", expected: change[:expected_account], actual: entry.account.name }
      end

      if change[:expected_current_category].present? && change[:expected_current_category] != current_category_name(transaction)
        mismatches << { field: "current_category", expected: change[:expected_current_category], actual: current_category_name(transaction) }
      end

      mismatches
    end

    def parse_amount(amount)
      BigDecimal(amount.to_s).abs
    rescue ArgumentError
      nil
    end

    def find_category(category_name)
      return nil if uncategorized?(category_name)

      family.categories.find_by(name: category_name)
    end

    def uncategorized?(category_name)
      category_name == "Uncategorized"
    end

    def apply_category!(transaction, category)
      transaction.set_category!(category)
      transaction.lock_attr!(:category_id)
      transaction.entry.mark_user_modified!
    end

    def transaction_result(transaction, index)
      entry = transaction.entry
      {
        index: index,
        transaction_id: transaction.id,
        entry_id: entry.id,
        date: entry.date,
        amount: entry.amount.abs,
        account: entry.account.name,
        name: entry.name,
        current_category: current_category_name(transaction),
        is_transfer: transaction.transfer?
      }
    end

    def base_result(change, index)
      {
        index: index,
        transaction_id: change[:transaction_id],
        entry_id: change[:entry_id]
      }
    end

    def current_category_name(transaction)
      transaction.category&.name || "Uncategorized"
    end

    def failure(error, message)
      {
        success: false,
        error: error,
        message: message
      }
    end

    def boolean_type
      @boolean_type ||= ActiveModel::Type::Boolean.new
    end
end
