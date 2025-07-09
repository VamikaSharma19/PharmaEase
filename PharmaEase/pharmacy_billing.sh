#!/bin/bash

SCRIPT_DIR="$(dirname "$0")"
LOG_FILE="$SCRIPT_DIR/pharmacy_billing.log"
MEDICINE_FILE="$SCRIPT_DIR/medicine_list.txt"
LOW_STOCK_THRESHOLD=10

log_action() {
  echo "[$(date)] $1" >> "$LOG_FILE"
}

view_medicines() {
  cut -d '|' -f 1 "$MEDICINE_FILE" > /tmp/medicine_list.txt

  zenity --text-info \
    --title="📋 Medicine Stock" \
    --filename="/tmp/medicine_list.txt" \
    --width=500 --height=400 \
    --ok-label="🔙 Back"

  log_action "Viewed only medicine names"
}

search_medicine() {
  keyword=$(zenity --entry \
    --title="🔍 Search Medicine" \
    --text="Enter the starting letters of the medicine name:")

  if [ -z "$keyword" ]; then
    zenity --error --title="⚠️ Error" --text="Search keyword cannot be empty!"
    return
  fi

  result=$(grep -i "^$keyword" "$MEDICINE_FILE" | cut -d '|' -f1)

  if [ -n "$result" ]; then
    zenity --info --title="🔎 Search Result" --text="✅ Found Medicines:\n\n$result"
    log_action "Searched medicine: $keyword"
  else
    zenity --error --title="❌ Not Found" --text="No medicines starting with '$keyword' found!"
  fi
}

check_low_stock() {
  medicine_name=$1
  stock_quantity=$2

  if ! [[ "$stock_quantity" =~ ^[0-9]+$ ]]; then
    return
  fi

  if [ "$stock_quantity" -lt "$LOW_STOCK_THRESHOLD" ]; then
    zenity --warning --title="⚠️ Low Stock Alert" --text="The stock of '$medicine_name' is low (only $stock_quantity remaining). Please restock soon!"
  fi
}

view_low_stock_medicines() {
  low_stock_list=$(awk -F'|' -v threshold="$LOW_STOCK_THRESHOLD" '$3 < threshold { printf "%s | Price: ₹%s | Stock: %s\n", $1, $2, $3 }' "$MEDICINE_FILE")

  if [ -n "$low_stock_list" ]; then
    zenity --info \
      --title="📉 Low Stock Medicines" \
      --text="These medicines are low in stock:\n\n$low_stock_list" --width=400
    log_action "Viewed low stock medicines"
  else
    zenity --info \
      --title="✅ Stock Check" \
      --text="All medicines are sufficiently stocked." --width=300
  fi
}

check_expiry() {
  today=$(date +%F)
  threshold=$(date -d "+3 days" +%F)

  expired=""
  expiring_soon=""

  while IFS='|' read -r name price stock expiry; do
    if [[ "$expiry" < "$today" ]]; then
      expired+="$name (Expired on $expiry)\n"
    elif [[ "$expiry" < "$threshold" ]]; then
      expiring_soon+="$name (Expiring on $expiry)\n"
    fi
  done < "$MEDICINE_FILE"

  if [ -n "$expired" ] || [ -n "$expiring_soon" ]; then
    msg=""
    [ -n "$expired" ] && msg+="⛔ EXPIRED:\n$expired\n"
    [ -n "$expiring_soon" ] && msg+="⚠️ EXPIRING SOON:\n$expiring_soon"

    zenity --warning --title="🧪 Expiry Alert" --text="$msg" --width=420 --height=300
    log_action "Checked expiry – expired or expiring soon medicines shown"
  else
    zenity --info --title="✅ All Medicines Fresh" --text="No medicines expired or expiring in the next 3 days."
  fi
}

add_medicine() {
  name=$(zenity --entry --title="➕ Add Medicine" --text="Enter medicine name:")
  if [ -z "$name" ]; then
    zenity --error --text="⚠️ Medicine name cannot be empty!"
    return
  fi

  price=$(zenity --entry --title="💰 Price Entry" --text="Enter price per packet:")
  if ! [[ "$price" =~ ^[0-9]+$ ]]; then
    zenity --error --text="⚠️ Please enter a valid numeric price."
    return
  fi

  stock=$(zenity --entry --title="📦 Stock Quantity" --text="Enter initial stock quantity:")
  if ! [[ "$stock" =~ ^[0-9]+$ ]]; then
    zenity --error --text="⚠️ Please enter a valid numeric stock quantity."
    return
  fi
  
  expiry=$(zenity --calendar \
    --title="📅 Expiry Date" \
    --text="Select expiry date of '$name':" \
    --date-format="%Y-%m-%d")
  
  if [ -z "$expiry" ]; then
    zenity --error --text="⚠️ Expiry date cannot be empty or improperly selected!"
    return
  fi

  today=$(date +%F)
  if [[ "$expiry" < "$today" ]]; then
    zenity --warning --text="⚠️ The selected expiry date is already past!\n\n'$name' is expired and will NOT be added.\nPlease re-check the date selection."
    return
  fi

  echo "$name|$price|$stock|$expiry" >> "$MEDICINE_FILE"
  zenity --info --text="✅ Medicine '$name' added at ₹ $price with $stock packets in stock."
  log_action "Added medicine: $name at ₹ $price with $stock packets"
  check_low_stock "$name" "$stock"
}

delete_medicine() {
  medicine_list=$(cut -d '|' -f 1 "$MEDICINE_FILE")

  if [ -z "$medicine_list" ]; then
    zenity --error --text="⚠️ No medicines available to delete."
    return
  fi

  selected=$(printf "%s\n" "$medicine_list" | zenity --list \
    --title="🗑️ Delete Medicine" \
    --column="Available Medicines" --height=300 --width=300)

  if [ -n "$selected" ]; then
    grep -v "^$selected|" "$MEDICINE_FILE" > "$MEDICINE_FILE.tmp" && mv "$MEDICINE_FILE.tmp" "$MEDICINE_FILE"
    zenity --info --text="🧹 '$selected' removed from stock."
    log_action "Deleted medicine: $selected"
  fi
}

modify_medicine() {
  selected=$(cut -d '|' -f 1 "$MEDICINE_FILE" | zenity --list \
    --title="✏️ Modify Medicine" \
    --column="Available Medicines" --height=300 --width=300)

  if [ -n "$selected" ]; then
    new_name=$(zenity --entry --title="Edit Name" --text="Rename '$selected':" --entry-text="$selected")
    new_price=$(zenity --entry --title="Edit Price" --text="New price for '$new_name':")
    new_stock=$(zenity --entry --title="Edit Stock" --text="New stock quantity for '$new_name':")
    new_expiry=$(zenity --calendar \
      --title="Edit Expiry Date" \
      --text="Select new expiry date for '$new_name':" \
      --date-format="%Y-%m-%d")

    if ! [[ "$new_price" =~ ^[0-9]+$ ]] || ! [[ "$new_stock" =~ ^[0-9]+$ ]]; then
      zenity --error --text="⚠️ Invalid price or stock quantity."
      return
    fi

    grep -v "^$selected|" "$MEDICINE_FILE" > "$MEDICINE_FILE.tmp"
    echo "$new_name|$new_price|$new_stock|$new_expiry" >> "$MEDICINE_FILE.tmp"
    mv "$MEDICINE_FILE.tmp" "$MEDICINE_FILE"
    zenity --info --text="📝 '$selected' updated to '$new_name' at ₹ $new_price with $new_stock packets"
    log_action "Modified $selected to $new_name at ₹ $new_price with $new_stock packets"
    check_low_stock "$new_name" "$new_stock"
  fi
}

generate_bill() {
  temp_bill="/tmp/pharmacy_bill.txt"
  {
    echo "=================================================="
    echo "                              BILL RECEIPT             "
    echo "=================================================="
    echo "Date: $(date)"
    echo "--------------------------------------------------"
    printf "%-20s %-10s %-10s %-10s\n" "Medicine" "Price" "Qty" "Subtotal"
    echo "--------------------------------------------------"
  } > "$temp_bill"

  total=0

  while true; do
    search_term=$(zenity --entry \
      --title="🔍 Search Medicines" \
      --text="Enter part of the medicine name to filter (or leave empty to show all):")

    if [ -n "$search_term" ]; then
      filtered_list=$(grep -i "^$search_term" "$MEDICINE_FILE" | cut -d '|' -f 1)
    else
      filtered_list=$(cut -d '|' -f 1 "$MEDICINE_FILE")
    fi

    if [ -z "$filtered_list" ]; then
      zenity --error --text="⚠️ No medicines found. Try again."
      continue
    fi

    medicine=$(echo "$filtered_list" | zenity --list \
      --title="🛒 Add to Bill" \
      --column="Select Medicine" --height=300 --width=300)

    [ -z "$medicine" ] && break

    price=$(grep "^$medicine|" "$MEDICINE_FILE" | cut -d '|' -f 2)
    quantity=$(zenity --entry --title="Enter Quantity" --text="How many packets of '$medicine'?")

    if ! [[ "$quantity" =~ ^[0-9]+$ ]]; then
      zenity --error --text="⚠️ Invalid quantity entered."
      continue
    fi

    current_stock=$(grep "^$medicine|" "$MEDICINE_FILE" | cut -d '|' -f 3)
    if [ "$current_stock" -lt "$quantity" ]; then
      zenity --warning --title="⚠️ Low Stock Warning" --text="Only $current_stock packets of '$medicine' are available, but you requested $quantity. Please adjust the quantity."
      continue
    fi

    expiry_date=$(grep "^$medicine|" "$MEDICINE_FILE" | cut -d '|' -f 4)
    today=$(date +%F)
    if [[ "$expiry_date" < "$today" ]]; then
      zenity --error --text="⚠️ The medicine '$medicine' has expired on $expiry_date and cannot be added to the bill."
      continue
    fi

    subtotal=$((price * quantity))
    total=$((total + subtotal))

    new_stock=$((current_stock - quantity))
    sed -i "s/^$medicine|[0-9]*|[0-9]*$/$medicine|$price|$new_stock/" "$MEDICINE_FILE"

    printf "%-20s ₹ %-8s %-10s ₹ %-8s\n" "$medicine" "$price" "$quantity" "$subtotal" >> "$temp_bill"

    add_more=$(zenity --question --title="Add More Medicine?" --text="Do you want to add more medicines to the bill?" --ok-label="Yes" --cancel-label="No")
    
    if [ $? -eq 1 ]; then
      break
    fi
  done

  echo "--------------------------------------------------" >> "$temp_bill"
  echo "Total Amount: ₹ $total" >> "$temp_bill"
  echo "==================================================" >> "$temp_bill"

  cat "$temp_bill" | zenity --text-info --title="💳 Pharmacy Bill" --width=500 --height=400
  log_action "Generated bill with total ₹$total"
}

exit_script() {
  zenity --question --title="🚪 Exit Confirmation" --text="Are you sure you want to exit?"
  if [ $? -eq 0 ]; then
    log_action "Exited Pharmacy Billing System"
    exit 0
  fi
}

# Main Menu
while true; do
  choice=$(zenity --list \
    --title="💊 Pharmacy Billing System" \
    --column="💼 Choose Operation" \
    --height=520 --width=450 \
    --print-column=1 \
    "📋 View Medicines" \
    "🔍 Search Medicine" \
    "📉 View Low Stock Medicines" \
    "⏳ Check Expired/Expiring Medicines" \
    "➕ Add Medicine to Stock" \
    "🗑️ Delete Medicine from Stock" \
    "✏️ Modify Medicine in Stock" \
    "🧾 Generate Bill" \
    "🚪 Exit")
    
  case "$choice" in
    "📋 View Medicines") view_medicines ;;
    "🔍 Search Medicine") search_medicine ;;
    "📉 View Low Stock Medicines") view_low_stock_medicines ;;
    "⏳ Check Expired/Expiring Medicines") check_expiry ;;
    "➕ Add Medicine to Stock") add_medicine ;;
    "🗑️ Delete Medicine from Stock") delete_medicine ;;
    "✏️ Modify Medicine in Stock") modify_medicine ;;
    "🧾 Generate Bill") generate_bill ;;
    "🚪 Exit") exit_script ;;
    *)
      if [ -z "$choice" ]; then
        exit_script
      else
        zenity --error --text="⚠️ Please make a valid selection."
      fi
      ;;
  esac
done