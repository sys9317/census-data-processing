/*==============================================================================
  PROJECT: Processing Census Data in Low-Resource Contexts
  AUTHOR:  Yosup Shin
  DATE:    February 2026
  
  OVERVIEW:
  This project demonstrates automated extraction and cleaning of census and
  administrative data from non-standard formats commonly encountered in
  developing countries:
  
  1. Pakistan District Census Data (Table 21): Automated extraction from 135 
     Excel sheets with inconsistent formatting
  2. Tanzania Student Exam Data: Extracting structured data from HTML strings
  
  These techniques are essential for research in contexts where government
  data systems have not been fully digitized or standardized.
==============================================================================*/

clear all
set more off

/*------------------------------------------------------------------------------
  SETUP: Define working directory paths
------------------------------------------------------------------------------*/

if c(username)=="Yosup" {
    global wd "/Users/yosupshin/Desktop/census-data-processing"
}

// Create output directories if they don't exist
cap mkdir "$wd/output"
cap mkdir "$wd/logs"

// Start log file
log using "$wd/logs/census_processing_`c(current_date)'.log", replace

/*==============================================================================
  PART 1: PAKISTAN DISTRICT CENSUS DATA (TABLE 21)
  
  CHALLENGE: Census data distributed across 135 Excel sheets (one per district)
  with inconsistent column alignment and formatting. Need to extract citizenship
  card data for adults (18+) and standardize across all districts.
  
  METHOD: Loop through all sheets, extract relevant rows, reshape, and
  standardize column names.
==============================================================================*/

display as text _newline(2) "=" * 80
display as text "PART 1: Processing Pakistan District Census Data"
display as text "=" * 80 _newline

global excel_t21 "$wd/data/q4_Pakistan_district_table21.xlsx"

// Create empty tempfile to store combined data
tempfile table21
save `table21', replace emptyok

// Loop through all 135 district sheets
display as text "Extracting data from 135 Excel sheets..."

forvalues i = 1/135 {
    
    // Import sheet as strings to preserve all data
    import excel "$excel_t21", sheet("Table `i'") firstrow clear allstring
    
    // Progress indicator
    if mod(`i', 10) == 0 {
        display as result "  Processed `i' of 135 sheets..."
    }
    
    // Extract only the "18 AND ABOVE" row using modern string function
    // FIX: Changed from regexm() to ustrregexm() (modern Stata syntax)
    keep if ustrregexm(TABLE21PAKISTANICITIZEN1, "18 AND")
    
    // Keep only first occurrence if multiple rows match
    keep in 1
    
    // Rename first column for consistency
    rename TABLE21PAKISTANICITIZEN1 table21
    
    // Create district identifier
    gen district = `i'
    
    // Append to master dataset
    append using `table21'
    save `table21', replace
}

// Load combined dataset
use `table21', clear

display as result _newline "Successfully extracted data from all 135 districts"
display as text "Observations: " as result _N

/*------------------------------------------------------------------------------
  Data Cleaning: Handle misaligned columns
------------------------------------------------------------------------------*/

display as text _newline "Cleaning misaligned columns..."

// Format columns for visibility
format %40s table21 B C D E F G H I K L M N O P Q R S T U V W X Y Z AA AB AC

// Remove empty cells and dash placeholders
// FIX: Improved regex pattern and added proper string trimming
local cols "B C D E F G H I K L M N O P Q R S T U V W X Y Z AA AB AC"

foreach var in `cols' {
    // Remove dashes (common placeholder in census forms)
    replace `var' = "" if ustrregexm(`var', "^-+$")
    // Remove cells with only whitespace
    replace `var' = "" if trim(`var') == ""
}

/*------------------------------------------------------------------------------
  Reshape: Convert wide format to long, then back to standardized wide
------------------------------------------------------------------------------*/

display as text "Reshaping data to standardize column positions..."

// Move district ID to end for reshape
order district, last
sort district

// Rename columns sequentially
local i = 1
foreach var of varlist B-Z AA-AC {
    rename `var' col`i'
    local i = `i' + 1
}

// Reshape to long format
reshape long col, i(district) j(temp_var) string
drop if col == ""
drop temp_var

// Create sequential variable number within each district
bysort district: gen variable = _n

// Reshape back to wide with standardized positions
reshape wide col, i(district) j(variable)

/*------------------------------------------------------------------------------
  Rename columns to meaningful variable names
------------------------------------------------------------------------------*/

display as text "Assigning meaningful variable names..."

// FIX: Added proper handling of missing columns and improved column assignments
local letters "A B C D E F G H I J K L"
local i = 1
foreach var of varlist col* {
    replace `var' = strtrim(`var')
    local newname: word `i' of `letters'
    capture rename `var' `newname'  // Added capture in case column doesn't exist
    local i = `i' + 1
}

// Standardize the age category label
replace table21 = "18 AND ABOVE" if ustrregexm(table21, "OVERALL|18 AND")

// Reorder and rename to meaningful names based on census structure
// FIX: Reordered columns to match actual data structure
order table21 F J K L A B C D E G H I
order district, first

rename F all_total_population
rename J all_cni_card_obtained
rename K all_cni_card_not_obtained
rename L male_total_population
rename A male_cni_card_obtained
rename B male_cni_card_not_obtained
rename C female_total_population
rename D female_cni_card_obtained
rename E female_cni_card_not_obtained
rename G trans_total_population
rename H trans_cni_card_obtained
rename I trans_cni_card_not_obtained

// Drop redundant age label column
drop table21

// Destring all numeric variables
// FIX: Added comprehensive destring with error handling
ds district, not
foreach var in `r(varlist)' {
    destring `var', replace force
}

/*------------------------------------------------------------------------------
  Data validation
------------------------------------------------------------------------------*/

display as text _newline "Running data quality checks..."

// Check for districts with missing data
count if missing(all_total_population)
if r(N) > 0 {
    display as error "Warning: `r(N)' districts have missing population data"
}

// Verify male + female totals match reported totals (allowing for rounding)
gen total_check = male_total_population + female_total_population + trans_total_population
gen diff = abs(all_total_population - total_check)
count if diff > 10 & !missing(diff)
if r(N) > 0 {
    display as error "Warning: `r(N)' districts have discrepancies in population totals"
}
drop total_check diff

/*------------------------------------------------------------------------------
  Save cleaned dataset
------------------------------------------------------------------------------*/

label data "Pakistan District Census Table 21: Citizenship Cards, Ages 18+"
save "$wd/output/pakistan_district_census_clean.dta", replace

display as result _newline "Pakistan census data cleaning complete!"
display as text "Output saved to: $wd/output/pakistan_district_census_clean.dta"

// Generate summary statistics
display as text _newline "Summary statistics by gender:"
tabstat all_total_population male_total_population female_total_population ///
    trans_total_population, statistics(mean sum min max) format(%12.0fc)

/*==============================================================================
  PART 2: TANZANIA STUDENT EXAM DATA (HTML EXTRACTION)
  
  CHALLENGE: Student roster and exam results stored as HTML strings in a
  Stata dataset. Need to extract structured data including school rankings,
  average scores, and individual student records.
  
  METHOD: Use regex pattern matching to extract numeric and text data from
  HTML-formatted strings.
==============================================================================*/

display as text _newline(2) "=" * 80
display as text "PART 2: Processing Tanzania Student Exam Data"
display as text "=" * 80 _newline

global school_level "$wd/data/q5_Tz_student_roster_html.dta"
use "$school_level", clear

display as text "Original observations: " as result _N

/*------------------------------------------------------------------------------
  Extract School-Level Statistics
------------------------------------------------------------------------------*/

display as text _newline "Extracting school-level statistics from HTML..."

// Remove all HTML tags
// FIX: Changed regexr() to ustrregexra() and fixed to remove ALL tags
replace s = ustrregexra(s, "<[^>]+>", "")

// Extract number of exam takers
// Pattern: "WALIOFANYA MTIHANI : [number]"
gen num_exam_takers = .
replace num_exam_takers = real(ustrregexs(1)) if ustrregexm(s, "WALIOFANYA MTIHANI\s*:\s*([0-9]+)")
label var num_exam_takers "Number of students who took exam"

// Extract school average score
// Pattern: "WASTANI WA SHULE : [decimal number]"
gen school_avg = .
replace school_avg = real(ustrregexs(1)) if ustrregexm(s, "WASTANI WA SHULE\s*:\s*([0-9]+\.?[0-9]*)")
label var school_avg "School average score"

// Generate student group indicator (under 40 vs 40+)
// FIX: Improved logic and added proper labeling
gen student_group = .
replace student_group = 0 if ustrregexm(s, "Wanafunzi chini ya ([0-9]+)") & real(ustrregexs(1)) < 40
replace student_group = 1 if ustrregexm(s, "Wanafunzi chini ya ([0-9]+)") & real(ustrregexs(1)) >= 40
label define group_lbl 0 "Under 40 students" 1 "40+ students"
label values student_group group_lbl
label var student_group "School size category"

// Extract school ranking within council
// Pattern: "NAFASI YA SHULE KWENYE KUNDI LAKE KIHALMASHAURI: [rank] kati ya [total]"
gen council_rank = .
gen council_total = .
replace council_rank = real(ustrregexs(1)) if ustrregexm(s, "NAFASI YA SHULE KWENYE KUNDI LAKE KIHALMASHAURI\s*:\s*([0-9]+)\s+kati\s+ya\s+([0-9]+)")
replace council_total = real(ustrregexs(2)) if ustrregexm(s, "NAFASI YA SHULE KWENYE KUNDI LAKE KIHALMASHAURI\s*:\s*([0-9]+)\s+kati\s+ya\s+([0-9]+)")
label var council_rank "School rank within council"
label var council_total "Total schools in council"

// Extract school ranking within region
// Pattern: "NAFASI YA SHULE KWENYE KUNDI LAKE KIMKOA : [rank] kati ya [total]"
gen region_rank = .
gen region_total = .
replace region_rank = real(ustrregexs(1)) if ustrregexm(s, "NAFASI YA SHULE KWENYE KUNDI LAKE KIMKOA\s*:\s*([0-9]+)\s+kati\s+ya\s+([0-9]+)")
replace region_total = real(ustrregexs(2)) if ustrregexm(s, "NAFASI YA SHULE KWENYE KUNDI LAKE KIMKOA\s*:\s*([0-9]+)\s+kati\s+ya\s+([0-9]+)")
label var region_rank "School rank within region"
label var region_total "Total schools in region"

// Extract national school ranking
// Pattern: "NAFASI YA SHULE KWENYE KUNDI LAKE KITAIFA : [rank] kati ya [total]"
gen national_rank = .
gen national_total = .
replace national_rank = real(ustrregexs(1)) if ustrregexm(s, "NAFASI YA SHULE KWENYE KUNDI LAKE KITAIFA\s*:\s*([0-9]+)\s+kati\s+ya\s+([0-9]+)")
replace national_total = real(ustrregexs(2)) if ustrregexm(s, "NAFASI YA SHULE KWENYE KUNDI LAKE KITAIFA\s*:\s*([0-9]+)\s+kati\s+ya\s+([0-9]+)")
label var national_rank "School rank nationally"
label var national_total "Total schools nationally"

// Extract school name and code
// Pattern: "[SCHOOL NAME] - PS[code]"
gen school_name = ustrregexs(1) if ustrregexm(s, "([A-Z][A-Z ]+)\s*-\s*PS[0-9]+")
gen school_code = ustrregexs(0) if ustrregexm(s, "(PS[0-9]+)")

// Clean up school name (remove extra spaces)
replace school_name = strtrim(school_name)

label var school_name "Name of school"
label var school_code "School identification code"

/*------------------------------------------------------------------------------
  Extract Student-Level Data
  
  FIX: This section has been completely rewritten to properly extract
  individual student records. The original code couldn't handle the multi-line
  structure of student records in the HTML.
------------------------------------------------------------------------------*/

display as text _newline "Extracting individual student records..."

// First, identify rows that contain student data
// Student records have candidate numbers in format: XXXX-XXXX-XXXXX (14 chars)
gen is_student = ustrregexm(s, "[A-Z0-9]{4}-[0-9]{4}-[0-9]{5}")

// Extract candidate number
gen cand_no = ustrregexs(0) if ustrregexm(s, "[A-Z0-9]{4}-[0-9]{4}-[0-9]{5}")

// Extract examination (premise) number (11 digits)
gen prem_no = ustrregexs(0) if ustrregexm(s, "[0-9]{11}")

// Extract gender (M or F)
// FIX: Improved pattern to avoid capturing random M/F in school names
gen gender = ustrregexs(1) if ustrregexm(s, ".*([MF])\s+[A-Z]{2,}")

// Extract student name
// FIX: Corrected pattern to capture full names (typically 2-3 words in caps)
gen student_name = ustrregexs(1) if ustrregexm(s, "([A-Z]+(?:\s+[A-Z]+){1,2})\s+Kiswahili")

// Extract subject grades using more specific patterns
// Each subject format: "Subject - Grade"
gen kiswahili = ustrregexs(1) if ustrregexm(s, "Kiswahili\s*-\s*([A-F])")
gen english = ustrregexs(1) if ustrregexm(s, "English\s*-\s*([A-F])")
gen maarifa = ustrregexs(1) if ustrregexm(s, "Maarifa\s*-\s*([A-F])")
gen hisabati = ustrregexs(1) if ustrregexm(s, "Hisabati\s*-\s*([A-F])")
gen science = ustrregexs(1) if ustrregexm(s, "Science\s*-\s*([A-F])")
gen uraia = ustrregexs(1) if ustrregexm(s, "Uraia\s*-\s*([A-F])")
gen average_grade = ustrregexs(1) if ustrregexm(s, "Average Grade\s*-\s*([A-F])")

// FIX: Collapse multiple rows per student into single observations
// Many student records span multiple rows in the HTML
display as text "Consolidating multi-row student records..."

// Sort by school and candidate number
gsort school_code cand_no -is_student

// For each student, fill down the extracted information
bysort school_code cand_no: replace prem_no = prem_no[_n-1] if missing(prem_no) & !missing(prem_no[_n-1])
bysort school_code cand_no: replace gender = gender[_n-1] if missing(gender) & !missing(gender[_n-1])
bysort school_code cand_no: replace student_name = student_name[_n-1] if missing(student_name) & !missing(student_name[_n-1])

// Collapse subject grades (take first non-missing value)
foreach subj in kiswahili english maarifa hisabati science uraia average_grade {
    bysort school_code cand_no: replace `subj' = `subj'[_n-1] if missing(`subj') & !missing(`subj'[_n-1])
}

// Keep only rows with complete student information
keep if !missing(cand_no) & !missing(student_name) & !missing(average_grade)

// Drop the original HTML string
drop s is_student

/*------------------------------------------------------------------------------
  Data validation and quality checks
------------------------------------------------------------------------------*/

display as text _newline "Running data quality checks..."

// Check for duplicate students
duplicates tag cand_no, gen(dup)
count if dup > 0
if r(N) > 0 {
    display as error "Warning: `r(N)' duplicate student records found"
    display as text "Keeping first occurrence only..."
    duplicates drop cand_no, force
}
drop dup

// Verify grade consistency
count if missing(average_grade) & !missing(kiswahili)
if r(N) > 0 {
    display as error "Warning: `r(N)' students have subject grades but no average"
}

// Label all grade variables
foreach subj in kiswahili english maarifa hisabati science uraia average_grade {
    label var `subj' "Grade for `subj'"
}

label var cand_no "Candidate number"
label var prem_no "Examination premise number"
label var gender "Student gender"
label var student_name "Student name"

/*------------------------------------------------------------------------------
  Save cleaned dataset
------------------------------------------------------------------------------*/

label data "Tanzania Student Exam Records with School Rankings"
save "$wd/output/tanzania_student_exams_clean.dta", replace

display as result _newline "Tanzania exam data extraction complete!"
display as text "Output saved to: $wd/output/tanzania_student_exams_clean.dta"
display as text "Total student records extracted: " as result _N

// Summary by school
display as text _newline "Schools in dataset:"
tab school_name, missing

display as text _newline "Average grades distribution:"
tab average_grade

/*==============================================================================
  PROJECT COMPLETION
==============================================================================*/

display as text _newline(2) "=" * 80
display as result "DATA PROCESSING COMPLETE"
display as text "=" * 80
display as text "Output files created:"
display as text "  1. $wd/output/pakistan_district_census_clean.dta"
display as text "  2. $wd/output/tanzania_student_exams_clean.dta"
display as text "  3. $wd/logs/census_processing_`c(current_date)'.log"
display as text "=" * 80

log close

/*==============================================================================
  END OF SCRIPT
==============================================================================*/
