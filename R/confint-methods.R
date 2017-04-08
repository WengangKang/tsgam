##' Point-wise and simultaneous confidence intervals for derivatives of smooths
##'
##' Calculates point-wise confidence or simultaneous intervals for the first derivatives of smooth terms in a fitted GAM.
##'
##' @param object an object of class `"fderiv"` containing the estimated derivatives.
##' @param parm which parameters (smooth terms) are to be given intervals as a vector of terms. If missing, all parameters are considered.
##' @param level numeric, `0 < level < 1`; the confidence level of the point-wise or simultaneous interval. The default is `0.95` for a 95\% interval.
##' @param type character; the type of interval to compute. One of `"confidence"` for point-wise intervals, or `"simultaneous"` for simultaneous intervals.
##' @param nsim integer; the number of simulations used in computing the simultaneous intervals.
##' @param ... additional arguments for methods
##'
##' @return a data frame with components:
##' 1. `term`; factor indicating to which term each row relates,
##' 2. `lower`; lower limit of the confidence or simultaneous interval,
##' 3. `est`; estimated derivative
##' 4. `upper`; upper limit of the confidence or simultaneous interval.
##'
##' @author Gavin L. Simpson
##'
##' @export
##'
##' @examples
##' library("mgcv")
##' set.seed(2)
##' dat <- gamSim(1, n = 400, dist = "normal", scale = 2)
##' mod <- gam(y ~ s(x0) + s(x1) + s(x2) + s(x3), data = dat, method = "REML")
##'
##' ## first derivatives of all smooths...
##' fd <- fderiv(mod)
##'
##' ## point-wise interval
##' ci <- confint(fd, type = "confidence")
##' head(ci)
##'
##' ## simultaneous interval for smooth term of x1
##' set.seed(42)
##' x1.sint <- confint(fd, parm = "x1", type = "simultaneous", nsim = 1000)
##' head(x1.sint)
`confint.fderiv` <- function(object, parm, level = 0.95,
                             type = c("confidence", "simultaneous"), nsim = 10000, ...) {
    ## Process arguments
    ## parm is one of the terms in object
    parm <- if(missing(parm)) {
        object$terms
    } else {
        terms <- object$terms
        want <- parm %in% terms
        if (any(!want)) {
            msg <- paste("Terms:", paste(parm[!want], collapse = ", "), "not found in `object`")
            stop(msg)
        }
        parm[want]
    }

    ## level should be length 1, numeric and 0 < level < 1
    if ((ll <- length(level)) > 1L) {
        warning(paste("`level` should be length 1, but supplied length: ",
                      ll, ". Using the first only."))
        level <- rep(level, length.out = 1L)
    }
    if (!is.numeric(level)) {
        stop(paste("`level` should be numeric, but supplied:", level))
    }
    if (! (0 < level) && (level < 1)) {
        stop(paste("`level` should lie in interval [0,1], but supplied:", level))
    }

    ## which type of interval is required
    type <- match.arg(type)

    ## generate intervals
    interval <- if (type == "confidence") {
        confidence(object, terms = parm, level = level)
    } else {
        simultaneous(object, terms = parm, level = level, nsim = nsim)
    }

    ## return
    interval
}

##' @importFrom stats quantile vcov
##' @importFrom MASS mvrnorm
`simultaneous` <- function(x, terms, level, nsim) {
    ## wrapper the computes each interval
    `simInt` <- function(x, Vb, bu, level, nsim) {
        Xi <- x[["Xi"]]           # derivative Lp, zeroed except for this term
        se <- x[["se.deriv"]]     # std err of deriv for current term
        d  <- x[["deriv"]]        # deriv for current term
        simDev <- Xi %*% t(bu)      # simulate deviations from expected
        absDev <- abs(sweep(simDev, 1, se, FUN = "/")) # absolute deviations
        masd <- apply(absDev, 2L, max)  # & maxabs deviation per sim
        ## simultaneous interval critical value
        crit <- quantile(masd, prob = level, type = 8)
        ## return as data frame
        data.frame(lower = d - (crit * se), est = d, upper = d + (crit * se))
    }

    ## bayesian covar matrix, possibly accounting for estimating smooth pars
    Vb <- vcov(x$model, unconditional = x$unconditional)
    ## simulate un-biased deviations given bayesian covar matrix
    buDiff <- MASS::mvrnorm(n = nsim, mu = rep(0, nrow(Vb)), Sigma = Vb)
    ## apply wrapper to compute simultaneous interval critical value and
    ## corresponding simultaneous interval for each term
    res <- lapply(x[["derivatives"]][terms], FUN = simInt,
                  Vb = Vb, bu = buDiff, level = level, nsim = nsim)
    ## how many values per term - currently all equal
    lens <- vapply(res, FUN = NROW, FUN.VALUE = integer(1))
    res <- do.call("rbind", res)        # row-bind each component of res
    res <- cbind(term = rep(terms, times = lens), res) # add on term ID
    rownames(res) <- NULL                              # tidy up
    res                                                # return
}

##' @importFrom stats qnorm
`confidence` <- function(x, terms, level) {
    ## wrapper the computes each interval
    `confInt` <- function(x, level) {
        se <- x[["se.deriv"]]     # std err of deriv for current term
        d  <- x[["deriv"]]        # deriv for current term
        ## confidence interval critical value
        crit <- qnorm(1 - ((1 - level) / 2))
        ## return as data frame
        data.frame(lower = d - (crit * se), est = d, upper = d + (crit * se))
    }

    ## apply wrapper to compute confidence interval critical value and
    ## corresponding confidence interval for each term
    res <- lapply(x[["derivatives"]][terms], FUN = confInt, level = level)
    ## how many values per term - currently all equal
    lens <- vapply(res, FUN = NROW, FUN.VALUE = integer(1))
    res <- do.call("rbind", res)        # row-bind each component of res
    res <- cbind(term = rep(terms, times = lens), res) # add on term ID
    rownames(res) <- NULL                              # tidy up
    res                                                # return
}

##' Point-wise and simultaneous confidence intervals for smooths
##'
##' Calculates point-wise confidence or simultaneous intervals for the smooth terms of a fitted GAM.
##'
##' @param object an object of class `"gam"` or `"gamm"`.
##' @param parm which parameters (smooth terms) are to be given intervals as a vector of terms. If missing, all parameters are considered, although this is not currently implemented.
##' @param level numeric, `0 < level < 1`; the confidence level of the point-wise or simultaneous interval. The default is `0.95` for a 95\% interval.
##' @param newdata data frame; containing new values of the covariates used in the model fit. The selected smooth(s) wil be evaluated at the supplied values.
##' @param type character; the type of interval to compute. One of `"confidence"` for point-wise intervals, or `"simultaneous"` for simultaneous intervals.
##' @param nsim integer; the number of simulations used in computing the simultaneous intervals.
##' @param shift logical; should the constant term be add to the smooth?
##' @param transform logical; should the smooth be evaluated on a transformed scale? For generalised models, this involves applying the inverse of the link function used to fit the model. Alternatively, the name of, or an actual, function can be supplied to transform the smooth and it's confidence interval.
##' @param unconditional logical; if `TRUE` (and `freq == FALSE`) then the Bayesian smoothing parameter uncertainty corrected covariance matrix is returned, if available.
##' @param ... additional arguments for methods
##'
##' @return a data frame with components:
##' 1. `term`; factor indicating to which term each row relates,
##' 2. `parm`; the vector of values at which the smooth was evaluated,
##' 3. `lower`; lower limit of the confidence or simultaneous interval,
##' 4. `est`; estimated value of the smooth
##' 5. `upper`; upper limit of the confidence or simultaneous interval.
##'
##' @author Gavin L. Simpson
##'
##' @importFrom stats family
##'
##' @export
##'
##' @examples
##' library("mgcv")
##' set.seed(2)
##' dat <- gamSim(1, n = 400, dist = "normal", scale = 2)
##' mod <- gam(y ~ s(x0) + s(x1) + s(x2) + s(x3), data = dat, method = "REML")
##'
##' ## point-wise interval
##' ci <- confint(mod, parm = "x1", type = "confidence")
##' head(ci)
##'
##' ## simultaneous interval for smooth term of x1
##' #set.seed(42)
##' #x1.sint <- confint(fd, parm = "x1", type = "simultaneous", nsim = 1000)
##' #head(x1.sint)
`confint.gam` <- function(object, parm, level = 0.95, newdata = NULL,
                          type = c("confidence", "simultaneous"), nsim = 10000,
                          shift = FALSE, transform = TRUE, unconditional = FALSE,
                          ...) {
    ## for now, insist on a single term
    if (missing(parm)) {
        stop("Currently 'parm' must be specified for 'confint.gam()'")
    } else {
        terms <- unlist(smooth_terms(object))
        want <- parm %in% terms
        if (any(!want)) {
            msg <- paste("Terms:", paste(parm[!want], collapse = ", "), "not found in `object`")
            stop(msg)
        }
        parm[want]
    }

    ## try to recover newdata from model if not supplied
    if (missing(newdata) || is.null(newdata)) {
        newdata <- object$model
    }

    type <- match.arg(type)

    ilink <- if (isTRUE(transform)) {
        family(object)$linkinv
    } else if (!is.null(transform)) {
        match.fun(transform)
    } else {
        function(eta) { eta }
    }

    if (isTRUE(type == "confidence")) {
        p <- predict(object, newdata = newdata, se.fit = TRUE, type = "terms")
        const <- attr(p, "constant")
        smooth.parm <- paste0("s(", parm, ")")
        fit <- p[["fit"]][, smooth.parm]
        if (shift) {
            fit + const
        }
        se.fit <- p[["se.fit"]][, smooth.parm]
        crit <- qnorm(1 - ((1 - level) / 2))
        out <- data.frame(term  = parm,
                          x     = newdata[, parm],
                          lower = ilink(fit - (crit * se.fit)),
                          est   = ilink(fit),
                          upper = ilink(fit + (crit * se.fit)))
    } else {
        Vb <- vcov(object, unconditional = unconditional)
        pred <- predict(object, newdata = newdata, se.fit = TRUE, type = "terms")
        se.fit <- pred$se.fit
    }

    ## return
    out
}