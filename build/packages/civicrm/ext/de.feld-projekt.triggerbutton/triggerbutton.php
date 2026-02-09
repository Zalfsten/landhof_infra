<?php
declare(strict_types = 1);

// phpcs:disable PSR1.Files.SideEffects
require_once 'triggerbutton.civix.php';
// phpcs:enable

use CRM_Triggerbutton_ExtensionUtil as E;

/**
 * Implements hook_civicrm_config().
 *
 * @link https://docs.civicrm.org/dev/en/latest/hooks/hook_civicrm_config/
 */
function triggerbutton_civicrm_config(\CRM_Core_Config $config): void {
  _triggerbutton_civix_civicrm_config($config);
}

/**
 * Implements hook_civicrm_install().
 *
 * @link https://docs.civicrm.org/dev/en/latest/hooks/hook_civicrm_install
 */
function triggerbutton_civicrm_install(): void {
  _triggerbutton_civix_civicrm_install();
}

/**
 * Implements hook_civicrm_enable().
 *
 * @link https://docs.civicrm.org/dev/en/latest/hooks/hook_civicrm_enable
 */
function triggerbutton_civicrm_enable(): void {
  _triggerbutton_civix_civicrm_enable();
}

/**
 * Implements hook_civicrm_permission().
 */
function triggerbutton_civicrm_permission(&$permissions) {
  $permissions['use triggerbutton'] = [
    'label' => ts('Use Triggerbutton'),
    'description' => ts('Allows a user to run the triggerbutton action.'),
  ];
}
