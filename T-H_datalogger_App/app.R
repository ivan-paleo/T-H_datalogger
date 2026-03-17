# Shiny app to summarize usage data at the IMPALA
# Process JSON exports from eLabFTW
# Written by Ivan Calandra

###############################################################################################################


#####################
# 1. Load libraries #
#####################

library(ggplot2)
library(patchwork)
library(readODS)
library(shiny)
library(tidyverse)
library(writexl)


###############################################################################################################


################
# 2. Define UI #
################

ui <- fluidPage(

  # 2.1. Application title
  titlePanel("Process Temperature-Humidity data from loggers"),

  sidebarLayout(

    # 2.2. Sidebar
    sidebarPanel(

      # Define settings of CSV file(s)
      # uiOutput() is necessary to allow updating for the error message if both separators are identical
      h5(HTML("<b>Choose the settings of your CSV file(s)</b>")),
      h5("If you are unsure, the easiest is to open a CSV file with a text editor and check"),
      splitLayout(cellWidths = c("50%", "50%"),
                  uiOutput("CSV_FieldSeparator"),
                  uiOutput("CSV_DecSeparator")
      ),

      # Show message if both separators are identical
      # uiOutput() is necessary to allow updating from the input
      uiOutput("CSV_Separators"),

      # Upload CSV file(s)
      fileInput("CSVfiles", "Choose CSV file(s) containing T-H data",
                multiple = TRUE, accept = ".csv"),
      h5(HTML("Make sure that the CSV files all have column names 'Date', 'Temparature', and 'Humidity'.<br><br> Dates must be specified following one of these formats: <ul><li>'dd/mm/YYYY HH:MM:SS' (e.g. '17/03/2026 15:26:00')</li><li>'YYYY-mm-dd HH:MM:SS' (e.g. '2026-03-17 15:26:00')</li></ul> For temperature and humidity, units can be specified in the column names (e.g. 'Temperature [°C]').")),

      # Select the period
      # uiOutput() is necessary to allow updating the range of dateRangeInput() from the imported CSV files
      uiOutput("period_range"),

      # Separator
      hr(style = "border-top: 1px solid #000000;"),

      # LEIZA logo
      img(src = "Leiza_Logo_Deskriptor_CMYK_rot_LEIZA.png", height = 150),

      # Credit
      # Separator
      hr(style = "border-top: 1px solid #000000;"),

      # Credit
      splitLayout(cellWidths = c("50%", "50%"),
                  actionButton("GitHub", "T-H_datalogger",
                               icon = icon("github", lib = "font-awesome"),
                               onclick = "window.open('https://github.com/ivan-paleo/T-H_datalogger', '_blank')"),
                  h5("By Ivan Calandra")),

      # Version number / date - ADJUST WITH NEW VERSION / DATE
      h5("v0.1 (2026-03-17)"),
      width = 3
    ),

    # 2.3. Main panel
    mainPanel(
      fluidRow(
        h2("Evolution of T and H over time for the selected period"),
        plotOutput("THplot"),
        downloadButton("downloadPDF", "Download plot to PDF"),
        downloadButton("downloadPNG", "Download plot to PNG"),

        hr(style = "border-top: 1px solid #000000;"),

        h2("Descriptive statistics of T and H data for the selected period"),
        tableOutput("TableStats"),
        downloadButton("downloadXLSX", "Download data to XLSX"),
        downloadButton("downloadODS", "Download data to ODS")
      )
    )
  )
)


###############################################################################################################


##########################
# 3. Define server logic #
##########################

server <- function(input, output) {

  # 3.1 Define settings of CSV file(s)
  # Field separator
  output$CSV_FieldSeparator <- renderUI({
    radioButtons("CSVsep", "Field separator",
                 choiceNames = c("semi-colon (;)", "comma (,)"),
                 choiceValues = c(";", ","))
  })

  # Decimal separator
  output$CSV_DecSeparator <- renderUI({
    radioButtons("CSVdec", "Decimal separator",
                 choiceNames = c("period (.)", "comma (,)"),
                 choiceValues = c(".", ","))
  })

  # Message if field and decimal separators are identical (comma)
  output$CSV_Separators <- renderUI({
    if (input$CSVsep == input$CSVdec) h5(HTML("<p style='color:red;'>Make sure to select different values for the field and decimal separators</p>"))
  })


  # 3.2 Read and format data
  # Use reactive() to use input file
  THdata <- reactive({

    # Ensure that CSV file(s) has been uploaded before proceeding
    req(input$CSVfiles)

    # Read uploaded CSV file(s)
    temp <- lapply(input$CSVfiles$datapath, read.table, header = TRUE, sep = input$CSVsep, dec = input$CSVdec) %>%

            # Combine them into one data.frame
            do.call(rbind, .) %>%

            # Convert to date format
            mutate(Date_f = as.Date(Date, tryFormats = c("%d/%m/%Y %H:%M:%S", "%Y-%m-%d %H:%M:%S"))) %>%

            # Select only T and H data
            select(Date = Date_f, `Temperature [°C]` = contains("Temperature"), `Humidity [%rH]` = contains("Humidity"))

    # return formatted TH data
    return(temp)
  })


  # 3.3 Extract date range of imported file for dateRangeInput()
  # Extract min and max via reactive()
  # necessary to allow updating
  min_val <- reactive({ min(THdata()[[1]], na.rm = TRUE) })
  max_val <- reactive({ max(THdata()[[1]], na.rm = TRUE) })

  # Define dateRangeInput() via renderUI()
  # necessary to allow updating
  output$period_range <- renderUI({
    dateRangeInput("THperiod", "Select the period", weekstart = 1,
                   start = min_val(), end = max_val(),
                   min = min_val(), max_val()
                  )
  })


  # 3.4 Output summary table of TH data
  # Filter data
  filter_THdata <- reactive({
    filter(THdata(), Date >= input$THperiod[1] & Date <= input$THperiod[2])
  })

  # Calculate summary stats
  summ_THdata <- reactive({
    temp2 <- do.call(cbind, lapply(filter_THdata()[2:3], summary, na.rm = TRUE))
    temp3 <- data.frame(row.names(temp2), temp2) %>%
             select(Stat = 1, `Temperature [°C]` = 2, `Humidity [%rH]` = 3)
  })

  # Render results
  output$TableStats <- renderTable({
    summ_THdata()
  })


  # 3.5 Output plot of TH data over time
  output$THplot <- renderPlot({
    pT <- ggplot(filter_THdata(), aes(x = Date, y = `Temperature [°C]`)) +
          geom_line(color = "#e41a1c") +
          labs(x = NULL) +
          theme_classic() + theme(legend.position = "none")

    pH <- ggplot(filter_THdata(), aes(x = Date, y = `Humidity [%rH]`)) +
          geom_line(color = "#377eb8") +
          labs(x = NULL) +
          theme_classic() + theme(legend.position = "none")

    p <- pT / pH
    print(p)
  })


  # 3.6 Define what happens when clicking on the download buttons
  # 3.6.1. Selected TH data to ODS
  output$downloadODS <- downloadHandler(

    # Create file name for file to be downloaded
    filename = function() {
      paste0("THdata_summary_", input$THperiod[1], "to", input$THperiod[2], ".ods")
    },

    # Define content
    content = function(file){
      readODS::write_ods(summ_THdata(), file)
    }
  )

  # 3.6.2. Selected TH data to XLSX
  output$downloadXLSX <- downloadHandler(
    filename = function() {
      paste0("THdata_summary_", input$THperiod[1], "to", input$THperiod[2], ".xlsx")
    },
    content = function(file){
      writexl::write_xlsx(summ_THdata(), file)
    }
  )

  # 3.6.3. Graph of selected TH data to PDF
  output$downloadPDF <- downloadHandler(
    filename = function() {
      paste0("THdata_plot_", input$THperiod[1], "to", input$THperiod[2], ".pdf")
    },
    content = function(file){
      ggsave(file, device = "pdf", width = 190, units = "mm")
    }
  )

  # 3.6.4. Graph of selected TH data to  PNG
  output$downloadPNG <- downloadHandler(
    filename = function() {
      paste0("THdata_plot_", input$THperiod[1], "to", input$THperiod[2], ".png")
    },
    content = function(file){
      ggsave(file, device = "png", width = 190, units = "mm")
    }
  )

}


###############################################################################################################


##########################
# 4. Run the application #
##########################

# Run the application
shinyApp(ui = ui, server = server)

# END OF CODE #
