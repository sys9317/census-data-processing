# Processing Census Data in Low-Resource Contexts

Automated extraction and cleaning of government administrative data from non-standard formats commonly encountered in developing countries.

---

## Overview

Government data in many low- and middle-income countries is often stored in inconsistent formats—Excel sheets with merged cells, HTML-formatted text files, PDFs with tables—making systematic analysis difficult. This project demonstrates techniques for programmatically extracting structured data from two real-world sources:

1. **Pakistan District Census Data:** 135 Excel sheets (one per district) with inconsistent column alignment
2. **Tanzania Student Exam Records:** HTML-formatted strings containing school rankings and individual student performance data

These skills are essential for researchers working on education, public health, economic development, or governance in contexts where digital infrastructure is still developing.

---

## Key Challenges Solved

### Challenge 1: Inconsistent Excel Formatting Across 135 Sheets
**Problem:** Each district's census data was stored in a separate Excel sheet with:
- Merged cells causing misaligned columns
- Mixed text and numeric data
- Placeholder dashes and empty cells
- No standardized column positions

**Solution:** 
- Automated loop extracts adult citizenship data from all 135 sheets
- Reshape operations standardize column positions
- Regex patterns remove placeholders and clean text
- Validation checks catch data quality issues

---

### Challenge 2: Structured Data Trapped in HTML Strings
**Problem:** Student exam results stored as HTML markup in a single text field:
- School-level statistics (rankings, averages) mixed with student records
- Multi-line student entries spanning multiple rows
- No delimiters or structured fields

**Solution:**
- Regex patterns extract school rankings at council, regional, and national levels
- Student-level extraction handles multi-row records
- Consolidation logic merges fragmented student data
- Duplicate detection ensures data quality

---

## Project Structure

```
census-data-processing/
├── census_data_processing.do      # Main Stata script
├── BUGS_FIXED.md                  # Detailed documentation of all fixes
├── data/
│   ├── q4_Pakistan_district_table21.xlsx
│   └── q5_Tz_student_roster_html.dta
├── output/
│   ├── pakistan_district_census_clean.dta
│   └── tanzania_student_exams_clean.dta
├── logs/
│   └── census_processing_[date].log
└── README.md
```

---

## Getting Started

### Prerequisites
- Stata 14 or later (uses modern regex functions)
- Excel data file for Pakistan census
- Stata dataset (.dta) containing HTML strings for Tanzania

### Setup

1. **Clone or download** this repository

2. **Update the working directory** in `census_data_processing.do`:
```stata
if c(username)=="YourUsername" {
    global wd "/path/to/your/project/folder"
}
```

3. **Place data files** in the `data/` folder

4. **Run the script:**
```stata
do census_data_processing.do
```

---

## Output Files

### 1. Pakistan District Census (Table 21)
**File:** `output/pakistan_district_census_clean.dta`

**Variables:**
- `district`: District identifier (1-135)
- `all_total_population`: Total population 18+
- `all_cni_card_obtained`: Adults with citizenship ID cards
- `all_cni_card_not_obtained`: Adults without citizenship ID
- Breakdowns by gender: `male_*`, `female_*`, `trans_*`

**Sample usage:**
```stata
use "output/pakistan_district_census_clean.dta", clear

// Calculate citizenship card coverage rate by gender
gen male_coverage = male_cni_card_obtained / male_total_population
gen female_coverage = female_cni_card_obtained / female_total_population

// Identify districts with low female ID card coverage
list district female_coverage if female_coverage < 0.5
```

---

### 2. Tanzania Student Exam Data
**File:** `output/tanzania_student_exams_clean.dta`

**School-level variables:**
- `school_name`, `school_code`
- `num_exam_takers`: Number of students tested
- `school_avg`: School average score
- `council_rank`: Rank within council (out of ~46 schools)
- `region_rank`: Rank within region (out of ~290 schools)
- `national_rank`: Rank nationally (out of ~5,664 schools)

**Student-level variables:**
- `cand_no`: Candidate ID number
- `student_name`, `gender`
- Subject grades: `kiswahili`, `english`, `maarifa`, `hisabati`, `science`, `uraia`
- `average_grade`: Overall letter grade (A-F)

**Sample usage:**
```stata
use "output/tanzania_student_exams_clean.dta", clear

// Analyze grade distribution by school
tab school_name average_grade, row

// Identify top-performing schools
gsort national_rank
list school_name school_avg national_rank in 1/10

// Gender performance gaps
bysort gender: sum average_grade
```

---

## Technical Details

### Modern Stata Syntax
This script uses **Stata 14+ Unicode regex functions:**
- `ustrregexm()` instead of deprecated `regexm()`
- `ustrregexs()` for capture groups
- `ustrregexra()` for replace-all operations

If you're using Stata 13 or earlier, you'll need to revert to the older functions (see `BUGS_FIXED.md` for details).

### Key Techniques Demonstrated

1. **Looping through multiple files**
```stata
forvalues i = 1/135 {
    import excel "$excel_t21", sheet("Table `i'") firstrow clear allstring
    // ... process ...
    append using `tempfile'
}
```

2. **Regex pattern matching for data extraction**
```stata
gen school_avg = real(ustrregexs(1)) if ustrregexm(s, "WASTANI WA SHULE\s*:\s*([0-9]+\.?[0-9]*)")
```

3. **Reshaping to standardize inconsistent formats**
```stata
reshape long col, i(district) j(temp_var)
// ... clean ...
reshape wide col, i(district) j(variable)
```

4. **Data validation and quality checks**
```stata
duplicates tag cand_no, gen(dup)
count if dup > 0
```

---

## Data Sources

### Pakistan Census Data
- **Source:** Pakistan Bureau of Statistics
- **Dataset:** Census Table 21 — Citizenship Card Status by Age and Gender
- **Coverage:** 135 districts
- **Year:** 2017 Census

### Tanzania Student Exam Data
- **Source:** National Examinations Council of Tanzania (NECTA)
- **Dataset:** Primary School Leaving Examination (PSLE) Results
- **Coverage:** Multiple schools, individual student records

---

## Next Steps & Extensions

### Potential Analyses

**Pakistan Census:**
- Map citizenship card coverage rates by district
- Analyze gender gaps in ID card access
- Link to development indicators (literacy, poverty, infrastructure)

**Tanzania Student Exams:**
- School value-added models (controlling for student demographics)
- Gender performance gaps by subject
- Regional disparities in educational quality
- Correlation between school resources and rankings

### Additional Data Integration
- Join Pakistan census data to district shapefiles for choropleth maps
- Link Tanzania school codes to administrative boundaries
- Merge with socioeconomic indicators (poverty rates, teacher qualifications)

---

## Skills Demonstrated

- **Data wrangling:** Cleaning messy, real-world government data
- **Automation:** Programmatic extraction from 135 files
- **Text processing:** Regex pattern matching on complex strings
- **Reshaping:** Converting between wide and long formats
- **Quality control:** Validation checks and duplicate detection
- **Documentation:** Clear code comments and error handling

---

## Contact

**Author:** Yosup Shin  
**GitHub:** [sys9317](https://github.com/sys9317)  
**Context:** Developed for Experimental Design course and Georgetown University Initiative on Innovation, Development and Evaluation 

---

*This project demonstrates real-world data skills needed for development economics, public health research, and governance analysis in low-resource settings.*
