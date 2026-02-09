<?php
use CRM_Triggerbutton_ExtensionUtil as E;
return [
    'triggerbutton_file_path' => [
        'name' => 'triggerbutton_file_path',
        'title' => E::ts('File path to touch when button is clicked'),
        'type' => 'String',
        'html_type' => 'text',
        'html_attributes' => [
            'class' => 'huge',
        ],
        'add' => '1.0',
        'is_domain' => 1,
        'is_contact' => 0,
        'help_text' => E::ts('File path to touch when button is clicked'),
        'settings_pages' => ['triggerbutton' => ['weight' => 15]],
        'default' => '/run/civicrm/triggerbutton.trigger',
    ],
    'triggerbutton_success_msg'=> [
        'name'=> 'triggerbutton_success_msg',
        'title'=> E::ts('Message displayed on successful trigger operation'),
        'type'=> 'String',
        'html_type'=> 'text',
        'html_attributes' => [
            'class' => 'huge',
        ],
        'add' => '1.0',
        'is_domain' => 1,
        'is_contact' => 0,
        'help_text'=> E::ts('Message displayed on successful trigger operation'),
        'settings_pages' => ['triggerbutton' => ['weight' => 16]],
        'default' => 'Trigger erfolgreich ausgeführt',
    ],
    'triggerbutton_failed_msg'=> [
        'name'=> 'triggerbutton_failed_msg',
        'title'=> E::ts('Message displayed on failed trigger operation'),
        'type'=> 'String',
        'html_type'=> 'text',
        'html_attributes' => [
            'class' => 'huge',
        ],
        'add' => '1.0',
        'is_domain' => 1,
        'is_contact' => 0,
        'help_text'=> E::ts('Message displayed on failed trigger operation'),
        'settings_pages' => ['triggerbutton' => ['weight' => 17]],
        'default' => 'Fehler beim Ausführen des Triggers',
    ],  
];