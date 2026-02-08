<?php

class CRM_Triggerbutton_Page_Run extends CRM_Core_Page {

  public function run() {
    if (!CRM_Core_Permission::check('use triggerbutton')) {
      // Benutzer hat nicht die notwendige Berechtigung
      CRM_Core_Session::setStatus(ts('You do not have permissions to use Triggerbutton.'), ts('Permission Denied'), 'error');
      CRM_Utils_System::redirect(CRM_Utils_System::url('civicrm'));
      return;
    }

    $path = Civi::settings()->get('triggerbutton_file_path');

    if (!$path) {
      CRM_Core_Session::setStatus(ts("Setting 'triggerbutton_file_path' fehlt!"), ts("Fehler"), "error");
    }
    elseif (!touch($path)) {
      $failed_msg = Civi::settings()->get('triggerbutton_failed_msg') ?: ts('Fehler beim Ausführen des Triggers');
      $details = ts("Datei konnte nicht geschrieben werden: $path");
      CRM_Core_Session::setStatus("$failed_msg\n$details", ts('Fehler'), "error");
    }
    else {
      $success_msg = Civi::settings()->get('triggerbutton_success_msg') ?: ts('Trigger erfolgreich ausgeführt');
      CRM_Core_Session::setStatus($success_msg, ts('OK'), "success");
    }

    $backUrl = $_SERVER['HTTP_REFERER'] ?? null;
    if ($backUrl && filter_var($backUrl, FILTER_VALIDATE_URL)) {
      CRM_Utils_System::redirect(CRM_Utils_System::url($backUrl));
    } else {
      // Fallback, falls kein Referer gesetzt ist
      CRM_Utils_System::redirect(CRM_Utils_System::url('civicrm'));
    }
  }

}
