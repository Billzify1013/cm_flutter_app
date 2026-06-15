// ===================================================================
//  Billzify - App configuration
//  Base URL aur saare API endpoints yahin se control hote hain.
// ===================================================================

class AppConfig {
  // ============ LIVE BASE URL ============
  // APIs live server pe hain - phone ko bas internet chahiye.
  // (localhost / adb reverse ki koi zaroorat nahi)
  static const String baseUrl = 'https://live.billzify.com';

  // ============ API ENDPOINTS (Django urls.py se match) ============
  static const String login = '/api_login/';
  static const String logout = '/api_logout/';
  static const String todayArrivals = '/api_todayarrivals/';
  static const String departures = '/api_departures/';
  static const String notifyBookings = '/api_notifybookings/';
  static const String searchBooking = '/api_searchbooking/';
  static const String tokenRefresh = '/api/token/refresh/';
  static const String inventory = '/api/inventory/management/';
  static const String checkBookingDates = '/api_check_booking_dates/';
  static const String saveBooking = '/api_save_booking/';
  static const String bookingDetail = '/api_booking_detail/';
  static const String addPayment = '/api_add_payment/';
  static const String editPayment = '/api_edit_payment/';
  static const String editGuest = '/api_edit_guest/';
  static const String editDates = '/api_edit_dates/';
  static const String editCommission = '/api_edit_commission/';
  static const String roomCategories = '/api_room_categories/';
  static const String changeCategory = '/api_change_category/';
  static const String posProducts = '/api_pos_products/';
  static const String posSave = '/api_pos_save/';
  static const String purchaseExpenseData = '/api_purchase_expense_data/';
  static const String supplierSave        = '/api_supplier_save/';
  static const String supplierDelete      = '/api_supplier_delete/';
  static const String purchaseSave        = '/api_purchase_save/';
  static const String purchaseDelete      = '/api_purchase_delete/';
  static const String purchaseItems       = '/api_purchase_items/';
  static const String expenseCategorySave = '/api_expense_category_save/';
  static const String expenseSave         = '/api_expense_save/';
  static const String expenseDelete       = '/api_expense_delete/';
  static const String stockLogs     = '/api_stock_logs/';
  static const String productCreate = '/api_product_create/';
  static const String productEdit   = '/api_product_edit/';
  static const String productDelete = '/api_product_delete/';
  static const String txnLogs = '/api_txn_logs/';
  static const String cancelBooking = '/api_cancel_booking/';
  static const String revokeBooking = '/api_revoke_booking/';
  static const String saveGuestGst = '/api_save_guest_gst/';
  static const String invoiceUnified = '/api_invoice_unified/';
  static const String createInvoice = '/api_create_invoice/';
  static const String cancelInvoice  = '/api_cancel_invoice/';
  static const String updateInvoiceGst = '/api_update_invoice_gst/';
  static const String editBill = '/api_edit_bill/';
  static const String saveFcmToken = '/api_save_fcm_token/';
  static const String salesReport    = '/api_sales_report/';
  static const String otaCommission  = '/api_ota_commission/';
  static const String salesReportDetailed = '/api_sales_report_detailed/';
  static const String hotelProfile = '/api_hotel_profile/';
  static const String notificationSettings = '/api_notification_settings/';
  static const String accounts = '/api_accounts/';
  static const String gstr1 = '/api_gstr1/';
  static const String gstr1Export = '/api_gstr1_export/';
  static const String gstr1ExportExcel = '/api_gstr1_export_excel/';
  static const String stayView = '/api/stay-view/';
  static const String pmsCheckin = '/api/pms/checkin/';
  static const String pmsCheckout = '/api/pms/checkout/';
  static const String pmsChangeRoom = '/api/pms/change-room/';
  static const String pmsUndoCheckin = '/api/pms/undo-checkin/';
  static const String pmsUndoCheckout = '/api/pms/undo-checkout/';
  static const String pmsAvailableRooms = '/api/pms/available-rooms/';
  static const String pmsRegistration = '/api/pms/registration/';
  static const String pmsRegistrationSave = '/api/pms/registration-save/';
}