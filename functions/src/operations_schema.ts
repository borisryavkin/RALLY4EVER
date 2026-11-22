// Source spreadsheet statuses, deduplicated without changing their wording.
export const operationsStatuses = [
  "Group",
  "Active",
  "Starting",
  "TBC",
  "Tentative",
  "In process",
  "Pending",
  "Unknown",
  "Prospective",
  "On hold",
  "Inactive",
  "Cancelled",
  "One-off",
];

// Shared admin-only spreadsheet schema; do not put these fields in public event/program documents.
export const operationsFields = [
  {
    group: "Programme",
    key: "location",
    label: "Location",
  },
  {
    group: "Programme",
    key: "stateSuburb",
    label: "State/Suburb",
  },
  {
    group: "Programme",
    key: "state",
    label: "State",
  },
  {
    group: "Programme",
    key: "status",
    label: "Status",
  },
  {
    group: "Programme",
    key: "scName",
    label: "SC Name",
  },
  {
    group: "Programme",
    key: "scActivities",
    label: "SC Activities",
  },
  {
    group: "Programme",
    key: "projectedAttendance",
    label: "Projected Attendance",
  },
  {
    group: "Programme",
    key: "attendance",
    label: "Attendance",
  },
  {
    group: "Programme",
    key: "communityServices",
    label: "Community Services Associated",
  },
  {
    group: "Programme",
    key: "communityContact",
    label: "Community Contact",
  },
  {
    group: "Programme",
    key: "expectedStartDate",
    label: "Expected Start Date",
  },
  {
    group: "Programme",
    key: "startDate",
    label: "Start Date",
  },
  {
    group: "Schedule and venue",
    key: "day",
    label: "Day",
  },
  {
    group: "Schedule and venue",
    key: "occurrence",
    label: "Occurance (During School Term)",
  },
  {
    group: "Schedule and venue",
    key: "frequency",
    label: "Frequency (During School Term)",
  },
  {
    group: "Schedule and venue",
    key: "time",
    label: "Time",
  },
  {
    group: "Schedule and venue",
    key: "tennisClubLocation",
    label: "Tennis Club/ Location",
  },
  {
    group: "Schedule and venue",
    key: "facilityName",
    label: "Facility Name/Org",
  },
  {
    group: "Schedule and venue",
    key: "tennisCentre",
    label: "Tennis Centre",
  },
  {
    group: "Schedule and venue",
    key: "address",
    label: "Address",
  },
  {
    group: "Schedule and venue",
    key: "postingAddress",
    label: "Posting address",
  },
  {
    group: "People and delivery",
    key: "coach",
    label: "Coach",
  },
  {
    group: "People and delivery",
    key: "coachName",
    label: "Coach name",
  },
  {
    group: "People and delivery",
    key: "coachContact",
    label: "Coach Contact",
  },
  {
    group: "People and delivery",
    key: "coachNumber",
    label: "Coach Number",
  },
  {
    group: "People and delivery",
    key: "contactName",
    label: "Contact name",
  },
  {
    group: "People and delivery",
    key: "contactFirstName",
    label: "Contact Name First",
  },
  {
    group: "People and delivery",
    key: "phone",
    label: "Phone",
  },
  {
    group: "People and delivery",
    key: "contactHash",
    label: "Contact #",
  },
  {
    group: "People and delivery",
    key: "contactNumber",
    label: "Contact number",
  },
  {
    group: "People and delivery",
    key: "contactEmail",
    label: "Contact email",
  },
  {
    group: "People and delivery",
    key: "subsidised",
    label: "Subsidised",
  },
  {
    group: "People and delivery",
    key: "teaCoffee",
    label: "Tea/Coffee",
  },
  {
    group: "People and delivery",
    key: "volunteer",
    label: "Volunteer",
  },
  {
    group: "People and delivery",
    key: "closedProgram",
    label: "Closed Program",
  },
  {
    group: "People and delivery",
    key: "posterDistributed",
    label: "Poster Distributed",
  },
  {
    group: "People and delivery",
    key: "qrCode",
    label: "QR Code",
  },
  {
    group: "Notes and community survey",
    key: "notes",
    label: "Notes",
  },
  {
    group: "Notes and community survey",
    key: "bernadetteNotes",
    label:
      "Notes (Bernadette phone calls end of 2025). Next columns on the right are part of survey run at the same time",
  },
  {
    group: "Notes and community survey",
    key: "progress",
    label: "How the program is going, # of participants",
  },
  {
    group: "Notes and community survey",
    key: "equipment",
    label: "Equipment or merchandise needed",
  },
  {
    group: "Notes and community survey",
    key: "issues",
    label: "Any issues - with coaches, participants",
  },
  {
    group: "Notes and community survey",
    key: "cuppa",
    label: "A cuppa afterward? Do they need $ or vouchers for this",
  },
  {
    group: "Notes and community survey",
    key: "outreach",
    label:
      "Do they need help reaching out to local community organisations for new participants",
  },
  {
    group: "Notes and community survey",
    key: "publicity",
    label:
      "Do they need a new poster, social media exposure,  RALLY4EVER coaching/ activities videos",
  },
  {
    group: "Notes and community survey",
    key: "whatsApp",
    label: "Is there a WhatsApp group set up?",
  },
  {
    group: "Notes and community survey",
    key: "impact",
    label: "How is the program impacting your local community",
  },
] as const;
