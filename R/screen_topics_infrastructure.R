# similar to import_shiny, but for initial load of data
load_topic_data <- function(
  data,
  stopwords
){

  if(missing(stopwords)){
    stopwords <- revwords()
  }else{
    if(is.null(stopwords)){
      stopwords <- revwords()
    }
  }

  x <- list(
    raw = NULL,
    stopwords = stopwords,
    columns = NULL,
    grouped = NULL,
    dtm = NULL,
    model = NULL,
    plot_ready = NULL
  )

  if(!is.null(data)){

    # throw a warning if a known file type isn't given
    accepted_inputs <- c(
      "bibliography",
      "data.frame",
      "screen_topics_progress"
    )
    if(!any(accepted_inputs == class(data))){
      stop("only classes 'bibliography', 'data.frame' or
      'screen_topics_progress' accepted by screen_topics")
    }

    # add data as necessary for that file type
    switch(class(data),
      "bibliography" = {
        result <- as.data.frame(data)
        colnames(result) <- clean_names(colnames(result))
        x$raw <- add_required_columns(result)
      },
      "data.frame" = {
        colnames(data) <- clean_names(colnames(data))
        x$raw <- add_required_columns(data)
      },
      "screen_topics_progress" = {
        x$raw <- data$raw
        x$stopwords <- data$stopwords
        x$columns <- data$columns
        x$grouped <- data$grouped
        x$dtm <- data$dtm
        x$model <- data$model
        x$plot_ready <- data$plot_ready
      }
    )

    # add colnames
    if(is.null(x$columns)){
      x$columns <- get_topic_colnames(x$raw)
    }

  } # end if(!is.null(data))

  # add user-defined stopwords if given
  if(!is.null(stopwords)){
    x$stopwords <- unique(c(
      x$stopwords,
      as.character(stopwords)
    ))
  }

  return(x)
}


build_plot_data <- function(info, dtm, model, hide_names){
  x_matrix <- modeltools::posterior(model)$topics # article x topic
  y_matrix <- t(modeltools::posterior(model)$terms)

  # exclude following columns: topic, select, display
  keep_cols <- which((colnames(info) %in% c("topic", "selected", "display")) == FALSE)

  # build main plot information (x)
  x_df <- cbind(
    info[, keep_cols],
    data.frame(
      topic = apply(x_matrix, 1, which.max),
      ade4::dudi.coa(x_matrix, scannf = FALSE, nf=3)$li
    )
  )

  # add citation in correctly formatted way
  x_df$caption <- paste0(
    add_line_breaks(
      format_citation(
        data = x_df,
        details = (hide_names == FALSE)
      )
    ),
    "<br>[Topic #",
    x_df$topic,
    "]"
  )
  x_df$common_words <- apply(dtm, 1, function(a){
    paste(
      names(sort(a, decreasing = TRUE)[1:5]),
      collapse = "; "
    )
  })
  x_df$text_color <- "#000000"

  # build word plot information (y)
  y_df <- data.frame(
    term = rep(
      x = colnames(dtm),
      times = model@k
    ),
    n = rep(
      x = apply(dtm, 2, sum),
      times = model@k
    ),
    topic = rep(
      x = seq_len(model@k),
      each = ncol(dtm)
    ),
    topic_weight = as.numeric(y_matrix),
    stringsAsFactors = FALSE
  )
  y_df$caption <- paste(
    "Term:", y_df$term, "<br>Sample size = ", y_df$n,
    sep = " "
  )
  y_list <- lapply(
    split(y_df, y_df$topic),
    function(a){
      a[order(a$topic_weight, decreasing = TRUE)[1:50], ]
    }
  )
  y_df <- as.data.frame(
    do.call(rbind, y_list),
    stringsAsFactors = FALSE
  )
  y_df$selected <- TRUE
  y_df$text_color <- "#000000"

  # calculate which topics are most likely, highest weighted, or both
  topics_default <- topicmodels::terms(model, 5)
  topics_weighted <- apply(
    y_matrix / apply(y_matrix, 1, sum), 2,
    function(a){names(sort(a, decreasing = TRUE)[1:5])
  })
  topic_caption_list <- lapply(
    seq_len(model@k),
    function(a, d, w){
      comparison <- w[, a] %in% d[, a]
      word_list <- list(
        "<em>high likelihood</em>" = d[!(d[, a] %in% w[, a]), a],
        "<em>high weight</em>" = w[!(w[, a] %in% d[, a]), a],
        "<em>both</em>" = w[w[, a] %in% d[, a], a]
      )
      word_vector <- unlist(lapply(
        word_list,
        function(b){paste(b, collapse = ", ")}
      ))
      result <- paste(
        paste(names(word_vector), word_vector, sep = ": "),
        collapse = "<br>"
      )
      return(result)
    },
    d = topics_default,
    w = topics_weighted
  )

  # add topic information
  topic_df <- data.frame(
    topic = seq_len(
      ncol(y_matrix)
    ),
    n = as.numeric(
      xtabs(~ topicmodels::topics(model))
    ),
    caption = apply(topics_default, 2, function(a){
      paste(a, collapse = ", ")
    }),
    caption_full = unlist(topic_caption_list),
    stringsAsFactors = FALSE
  )
  topic_df$text_color <- "#000000"

  # return
  plot_list <- list(
    x = x_df,
    y = y_df,
    topic = topic_df
  )
  return(plot_list)
}


add_required_columns <- function(data){
  added_cols <- data.frame(
    selected = NA,
    display = TRUE,
    topic = NA,
    notes = NA
  )
  col_check <- colnames(added_cols) %in% colnames(data)
  if(any(!col_check)){
    data <- as.data.frame(
      cbind(
        data,
        added_cols[, which(!col_check)]
      ),
      stringsAsFactors = FALSE
    )
  }
  return(data)
}

# function to cleanly extract colnames of interest from supplied datasets
get_topic_colnames <- function(data){
  colnames(data)[
    which(
      (colnames(data) %in%
      c("selected", "topic", "display", "notes")) == FALSE
    )
  ]
}

build_appearance <- function(plot_data, palette){
  lapply(plot_data, function(a, colours){
    result <- data.frame(
      id = a[, 1],
      topic = a$topic,
      color = palette[a$topic],
      stringsAsFactors = FALSE
    )
    if(any(colnames(a) == "text_color")){
      if(any(a$text_color == "#405d99")){
        result$color[which(a$text_color == "#405d99")] <- "#000000"
      }
      if(any(a$text_color == "#993f3f")){
        result$color[which(a$text_color == "#993f3f")] <- "#CCCCCC"
      }
    }
    return(result)
  },
  colours = palette)
}


update_appearance <- function(plot_data, palette){
  lapply(plot_data, function(a, colours){
    rows <- which(
      (a$color %in% c("#000000", "#CCCCCC")) == FALSE
    )
    a$color[rows] <- colours[a$topic[rows]]
    return(a)
    },
    colours = palette
  )
}