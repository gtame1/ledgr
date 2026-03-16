defmodule LedgrWeb.Domains.VolumeStudio.PaymentFormComponent do
  @moduledoc """
  Shared payment-recording form used by both Subscriptions and Space Rentals.

  Renders:
    1. A ledger-style payment summary (rows passed in by the caller).
    2. A payment form (amount, date, method, note).
    3. An overpayment section with three options: keep / record AP / staff gave change.
    4. The supporting JavaScript that shows/hides the overpayment section.

  ## Summary row format

  Each entry in `summary_rows` is a map with:
    - `:label`       — string, displayed on the left
    - `:value_cents` — integer cents, nil for non-currency rows
    - `:text`        — string override when `:value_cents` is nil (e.g. date ranges)
    - `:style`       — one of :normal | :discount | :total_row | :danger | :success | :muted
  """

  use Phoenix.Component
  import LedgrWeb.CoreComponents, only: [format_currency: 1]

  attr :summary_rows,        :list,    required: true
  attr :outstanding_cents,   :integer, required: true
  attr :default_amount_cents,:integer, required: true
  attr :payer_label,         :string,  default: "Customer"
  attr :action,              :string,  required: true
  attr :back_path,           :string,  required: true
  attr :change_accounts,     :list,    required: true
  attr :paid_to_accounts,    :list,    default: []

  def payment_form(assigns) do
    ~H"""
    <%!-- ── Payment Summary ───────────────────────────────────────────── --%>
    <section class="card" style="margin-bottom: 1.5rem;">
      <h3 class="ledger-title">Payment Summary</h3>
      <div class="ledger-rows">
        <%= for row <- @summary_rows do %>
          <div class={"ledger-row #{row_class(row.style)}"}>
            <span class="ledger-label"><%= row.label %></span>
            <span class={"ledger-value #{value_class(row.style)}"}>
              <%= cond do %>
                <% row[:text] != nil -> %>
                  <%= row.text %>
                <% row.style == :discount -> %>
                  − <%= format_currency(row.value_cents) %>
                <% true -> %>
                  <%= format_currency(row.value_cents) %>
              <% end %>
            </span>
          </div>
        <% end %>
      </div>
    </section>

    <%!-- ── Payment Form ──────────────────────────────────────────────── --%>
    <section class="card">
      <h3 class="card-title" style="font-size: 1rem; margin-bottom: 1.25rem;">Payment Details</h3>

      <form action={@action} method="post">
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <input type="hidden" name="payment[owed_change_choice]" id="owed_change_choice_input" value="keep" />

        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 1rem; margin-bottom: 1rem;">

          <div class="field">
            <label for="payment_amount">Amount (MXN) *</label>
            <div style="position: relative;">
              <span style="position: absolute; left: 0.75rem; top: 50%; transform: translateY(-50%); color: var(--text-muted); font-weight: 500;">$</span>
              <input
                id="payment_amount"
                type="number"
                name="payment[amount]"
                step="0.01"
                min="0.01"
                required
                value={:erlang.float_to_binary(@default_amount_cents / 100, [{:decimals, 2}])}
                style="padding-left: 1.75rem;"
                class="form-input"
              />
            </div>
          </div>

          <div class="field">
            <label for="payment_date">Payment Date *</label>
            <input
              id="payment_date"
              type="date"
              name="payment[payment_date]"
              required
              value={Date.utc_today() |> Date.to_iso8601()}
              class="form-input"
            />
          </div>

          <div class="field">
            <label for="payment_method">Method</label>
            <select id="payment_method" name="payment[method]" class="form-input">
              <option value="">— Select —</option>
              <option value="cash">Cash</option>
              <option value="card">Card</option>
              <option value="transfer">Transfer</option>
              <option value="other">Other</option>
            </select>
          </div>

          <%= if @paid_to_accounts != [] do %>
            <div class="field">
              <label for="payment_paid_to_account_code">Paid to *</label>
              <select id="payment_paid_to_account_code" name="payment[paid_to_account_code]" class="form-input">
                <%= for {label, code} <- @paid_to_accounts do %>
                  <option value={code}><%= label %></option>
                <% end %>
              </select>
            </div>
          <% end %>

          <div class="field" style="grid-column: 1 / -1;">
            <label for="payment_note">Note (optional)</label>
            <textarea
              id="payment_note"
              name="payment[note]"
              rows="2"
              placeholder="e.g. Paid at front desk"
              class="form-input"
            ></textarea>
          </div>

        </div>

        <%!-- ── Overpayment section ──────────────────────────────────── --%>
        <div id="overpayment-section" style="display:none; padding: 1rem; background: #fefce8; border: 1px solid #fde047; border-radius: var(--radius-md, 0.5rem); margin-bottom: 1.25rem;">
          <p style="font-size: 0.875rem; font-weight: 600; margin-bottom: 0.75rem; color: #92400e;">
            <%= @payer_label %> is paying <strong id="overpayment-amount-display">$0.00</strong> more than owed — how should we handle it?
          </p>
          <div style="display: flex; flex-direction: column; gap: 0.4rem;">
            <label style="display: flex; align-items: center; gap: 0.5rem; font-size: 0.875rem; cursor: pointer;">
              <input type="radio" name="owed_change_radio" value="keep" checked />
              Keep the extra (applied to balance)
            </label>
            <label style="display: flex; align-items: center; gap: 0.5rem; font-size: 0.875rem; cursor: pointer;">
              <input type="radio" name="owed_change_radio" value="record" />
              Record as owed change — we owe the <%= String.downcase(@payer_label) %> change (creates AP entry)
            </label>
            <label style="display: flex; align-items: center; gap: 0.5rem; font-size: 0.875rem; cursor: pointer;">
              <input type="radio" name="owed_change_radio" value="staff_gave_change" />
              Staff already gave the <%= String.downcase(@payer_label) %> their change
            </label>
          </div>

          <div id="change-given-section" style="display:none; margin-top: 0.75rem; padding-top: 0.75rem; border-top: 1px solid #fde047;">
            <p style="font-size: 0.8rem; font-weight: 600; margin-bottom: 0.5rem; color: #92400e;">Change details</p>
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 0.75rem;">
              <div class="field">
                <label for="payment_change_given" style="font-size: 0.8rem;">Amount Given Back (MXN)</label>
                <div style="position: relative;">
                  <span style="position: absolute; left: 0.75rem; top: 50%; transform: translateY(-50%); color: var(--text-muted); font-weight: 500;">$</span>
                  <input
                    id="payment_change_given"
                    type="number"
                    name="payment[change_given]"
                    step="0.01"
                    min="0"
                    value="0.00"
                    style="padding-left: 1.75rem;"
                    class="form-input"
                  />
                </div>
              </div>
              <div class="field">
                <label for="payment_change_from_account" style="font-size: 0.8rem;">Change Taken From</label>
                <select id="payment_change_from_account" name="payment[change_from_account]" class="form-input">
                  <option value="">— Select Account —</option>
                  <%= for {label, account_id} <- @change_accounts do %>
                    <option value={account_id}><%= label %></option>
                  <% end %>
                </select>
              </div>
            </div>
          </div>
        </div>

        <div style="display: flex; gap: 0.75rem;">
          <button type="submit" class="btn primary">Record Payment</button>
          <.link navigate={@back_path} class="btn">Cancel</.link>
        </div>
      </form>
    </section>

    <script>
      (function () {
        var outstandingCents   = <%= @outstanding_cents %>;
        var amountInput        = document.getElementById("payment_amount");
        var section            = document.getElementById("overpayment-section");
        var display            = document.getElementById("overpayment-amount-display");
        var hiddenInput        = document.getElementById("owed_change_choice_input");
        var radios             = document.querySelectorAll("input[name='owed_change_radio']");
        var changeGivenSection = document.getElementById("change-given-section");
        var changeGivenInput   = document.getElementById("payment_change_given");

        function formatMXN(cents) {
          return "$" + (cents / 100).toFixed(2) + " MXN";
        }

        function syncHiddenInput() {
          for (var i = 0; i < radios.length; i++) {
            if (radios[i].checked) { hiddenInput.value = radios[i].value; break; }
          }
        }

        function selectedRadioValue() {
          for (var i = 0; i < radios.length; i++) {
            if (radios[i].checked) return radios[i].value;
          }
          return "keep";
        }

        function updateChangeGivenSection() {
          changeGivenSection.style.display =
            selectedRadioValue() === "staff_gave_change" ? "block" : "none";
        }

        function checkOverpayment() {
          var amountCents = Math.round(parseFloat(amountInput.value || "0") * 100);
          var changeCents = amountCents - outstandingCents;

          if (changeCents > 0) {
            display.textContent = formatMXN(changeCents);
            section.style.display = "block";
            if (selectedRadioValue() === "staff_gave_change") {
              changeGivenInput.value = (changeCents / 100).toFixed(2);
            }
          } else {
            section.style.display = "none";
            changeGivenSection.style.display = "none";
            hiddenInput.value = "keep";
            for (var i = 0; i < radios.length; i++) {
              radios[i].checked = (radios[i].value === "keep");
            }
          }
          syncHiddenInput();
        }

        amountInput.addEventListener("input", checkOverpayment);

        for (var i = 0; i < radios.length; i++) {
          radios[i].addEventListener("change", function () {
            syncHiddenInput();
            var amountCents = Math.round(parseFloat(amountInput.value || "0") * 100);
            var changeCents = amountCents - outstandingCents;
            if (this.value === "staff_gave_change" && changeCents > 0) {
              changeGivenInput.value = (changeCents / 100).toFixed(2);
            }
            updateChangeGivenSection();
          });
        }

        checkOverpayment();
      })();
    </script>
    """
  end

  defp row_class(:total_row), do: "ledger-row--total"
  defp row_class(:danger),    do: "ledger-row--danger"
  defp row_class(:success),   do: "ledger-row--success"
  defp row_class(_),          do: ""

  defp value_class(:discount), do: "ledger-value--discount"
  defp value_class(_),         do: ""
end
