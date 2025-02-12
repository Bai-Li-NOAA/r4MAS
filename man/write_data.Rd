% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/write_data.R
\name{write_data}
\alias{write_data}
\title{This function writes a JSON data input file for MAS}
\usage{
write_data(data_list, outfile_path)
}
\arguments{
\item{data_list}{the list of data inputs, where each list slot corresponds to a data type needed by MAS}

\item{outfile_path}{the path to the data file you want to write. This should end with a .json file extension.}
}
\value{
the string containing the json data file to write.
}
\description{
This function writes a JSON data input file for MAS
}
