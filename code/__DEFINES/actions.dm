///Action button checks if hands are unusable
#define AB_CHECK_HANDS_BLOCKED (1 << 0)
///Action button checks if user is immobile
#define AB_CHECK_IMMOBILE (1 << 1)
///Action button checks if user is resting
#define AB_CHECK_LYING (1 << 2)
///Action button checks if user is conscious
#define AB_CHECK_CONSCIOUS (1 << 3)
///Action button checks if user is phasing
#define AB_CHECK_PHASED (1 << 4)

DEFINE_BITFIELD(check_flags, list(
	"CHECK IF HANDS BLOCKED" = AB_CHECK_HANDS_BLOCKED,
	"CHECK IF IMMOBILIZED" = AB_CHECK_IMMOBILE,
	"CHECK IF LYING DOWN" = AB_CHECK_LYING,
	"CHECK IF CONSCIOUS" = AB_CHECK_CONSCIOUS,
	"CHECK IF TEMPORARILY INCORPOREAL" = AB_CHECK_PHASED,
))

///Action button triggered with right click
#define TRIGGER_SECONDARY_ACTION (1<<0)

#define ACTION_BUTTON_DEFAULT_BACKGROUND "_use_ui_default_background"

#define UPDATE_BUTTON_NAME (1<<0)
#define UPDATE_BUTTON_ICON (1<<1)
#define UPDATE_BUTTON_BACKGROUND (1<<2)
#define UPDATE_BUTTON_OVERLAY (1<<3)
#define UPDATE_BUTTON_STATUS (1<<4)
